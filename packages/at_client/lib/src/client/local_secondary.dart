import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

/// Contains methods to execute verb on local secondary storage using [executeVerb]
/// Set [AtClientPreference.isLocalStoreRequired] to true and other preferences that your app needs.
/// Delete and Update commands will be synced to the server
class LocalSecondary implements Secondary {
  final AtClient _atClient;

  late final AtSignLogger _logger;

  /// Local keystore used to store data for the current atSign.
  SecondaryKeyStore? keyStore;

  LocalSecondary(this._atClient, {this.keyStore}) {
    _logger = AtSignLogger('LocalSecondary (${_atClient.getCurrentAtSign()})');
    keyStore ??= SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(_atClient.getCurrentAtSign())!
        .getSecondaryKeyStore();
  }

  @experimental
  AtTelemetryService? telemetry;

  /// Executes a verb builder on the local secondary. For update and delete operation, if [sync] is
  /// set to true then data is synced from local to remote.
  /// if [sync] is set to false, no sync operation is done.
  @override
  Future<String?> executeVerb(VerbBuilder builder, {sync}) async {
    String? verbResult;

    try {
      if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
        //1. if local and server are out of sync, first sync before updating current key-value
        //2 . update/delete to local store
        if (builder is UpdateVerbBuilder) {
          verbResult = await _update(builder);
        } else if (builder is DeleteVerbBuilder) {
          verbResult = await _delete(builder);
        }
        // 3. sync latest update/delete if strategy is immediate
        if (sync != null && sync) {
          _logger.finer('calling sync immediate from local secondary');
          _atClient.syncService.sync();
        }
      } else if (builder is LLookupVerbBuilder) {
        verbResult = await _llookup(builder);
      } else if (builder is ScanVerbBuilder) {
        verbResult = await _scan(builder);
      }
    } on AtLookUpException catch (e) {
      // Catches AtLookupException and
      // converts to AtClientException. rethrows any other exception.
      throw (AtClientException(e.errorCode, e.errorMessage));
    }
    return verbResult;
  }

  Future<String> _update(UpdateVerbBuilder builder) async {
    try {
      dynamic updateResult;
      var updateKey = builder.buildKey();
      switch (builder.operation) {
        case UPDATE_META:
          AtMetaData atMetadata = _getAtMetadataFromVerbBuilder(builder);
          atMetadata = await _unsetOrRetainAtMetadata(updateKey, atMetadata);
          updateResult = await keyStore!.putMeta(updateKey, atMetadata);
          break;
        default:
          var atData = AtData();
          atData.data = builder.value;
          AtMetaData atMetadata = _getAtMetadataFromVerbBuilder(builder);
          atMetadata = await _unsetOrRetainAtMetadata(updateKey, atMetadata);
          updateResult = await keyStore!.putAll(updateKey, atData, atMetadata);
          break;
      }
      return 'data:$updateResult';
    } on DataStoreException catch (e) {
      _logger.severe('exception in local update:${e.toString()}');
      rethrow;
    }
  }

  Future<AtMetaData> _unsetOrRetainAtMetadata(
      String atKey, AtMetaData currentAtMetaData) async {
    AtMetaData? existingMetadata = await keyStore!.getMeta(atKey);
    if (existingMetadata == null) {
      return currentAtMetaData;
    }

    var atMetaDataJson = currentAtMetaData.toJson();
    var existingAtMetaDataJson = existingMetadata.toJson();

    atMetaDataJson.forEach((key, value) {
      switch (value) {
        // If command does not contains the attributes of a metadata, then regex named
        // group, inserts null. For a key, if an attribute has a value in previously,
        // fetch the value and update it.
        case null:
          if (existingAtMetaDataJson[key] != null) {
            atMetaDataJson[key] = existingAtMetaDataJson[key];
          }
          break;
        // In the command, if an attribute is explicitly set to null, then verbParams
        // contains String value "null". Then reset the metadata. So, set it to null
        case 'null':
          atMetaDataJson[key] = null;
          break;
      }
    });
    return AtMetaData.fromJson(atMetaDataJson);
  }

  AtMetaData _getAtMetadataFromVerbBuilder(UpdateVerbBuilder builder) {
    var metadata = Metadata();
    metadata
      ..ttl = builder.ttl
      ..ttb = builder.ttb
      ..ttr = builder.ttr
      ..ccd = builder.ccd
      ..isBinary = builder.isBinary
      ..isEncrypted = builder.isEncrypted
      ..dataSignature = builder.dataSignature
      ..sharedKeyEnc = builder.sharedKeyEncrypted
      ..pubKeyCS = builder.pubKeyChecksum
      ..encoding = builder.encoding
      ..encKeyName = builder.encKeyName
      ..encAlgo = builder.encAlgo
      ..ivNonce = builder.ivNonce
      ..skeEncKeyName = builder.skeEncKeyName
      ..skeEncAlgo = builder.skeEncAlgo;
    return AtMetaData.fromCommonsMetadata(metadata);
  }

  Future<String> _llookup(LLookupVerbBuilder builder) async {
    var llookupKey = '';
    try {
      llookupKey = builder.buildKey();
      var llookupMeta = await keyStore!.getMeta(llookupKey);
      var isActive = _isActiveKey(llookupMeta);
      String? result;
      if (isActive) {
        var llookupResult = await keyStore!.get(llookupKey);
        result = _prepareResponseData(builder.operation, llookupResult);
      }
      return 'data:$result';
    } on DataStoreException catch (e) {
      _logger.severe('exception in llookup:${e.toString()}');
      rethrow;
    } on KeyNotFoundException catch (e) {
      e.stack(AtChainedException(
          Intent.fetchData, ExceptionScenario.keyNotFound, e.message));
      rethrow;
    }
  }

  Future<String> _delete(DeleteVerbBuilder builder) async {
    try {
      var deleteResult = await keyStore!.remove(builder.buildKey());
      return 'data:$deleteResult';
    } on DataStoreException catch (e) {
      _logger.severe('exception in delete:${e.toString()}');
      rethrow;
    }
  }

  Future<String?> _scan(ScanVerbBuilder builder) async {
    try {
      // Call to remote secondary sever and performs an outbound scan to retrieve values from sharedBy secondary
      // shared with current atSign
      if (builder.sharedBy != null) {
        var command = builder.buildCommand();
        return _atClient
            .getRemoteSecondary()!
            .executeCommand(command, auth: true);
      }
      List<String?> keys;
      keys = keyStore!.getKeys(regex: builder.regex) as List<String?>;
      // Gets keys shared to sharedWith atSign.
      if (builder.sharedWith != null) {
        keys.retainWhere(
            (element) => element!.startsWith(builder.sharedWith!) == true);
      }
      keys.removeWhere((key) => _shouldHideKeys(key!, builder.showHiddenKeys));
      var keyString = keys.toString();
      // Apply regex on keyString to remove unnecessary characters and spaces
      keyString = keyString.replaceFirst(RegExp(r'^\['), '');
      keyString = keyString.replaceFirst(RegExp(r'\]$'), '');
      keyString = keyString.replaceAll(', ', ',');
      var keysArray = keyString.isNotEmpty ? (keyString.split(',')) : [];
      return json.encode(keysArray);
    } on DataStoreException catch (e) {
      _logger.severe('exception in scan:${e.toString()}');
      rethrow;
    }
  }

  bool _shouldHideKeys(String key, bool showHiddenKeys) {
    // If showHidden is set to true, display hidden public keys.
    // So returning false
    if ((key.toString().startsWith('public:__') || key.startsWith('_')) &&
        showHiddenKeys) {
      return false;
    }
    // Do not display keys that starts with 'private:' or 'privatekey:' or public:_
    return key.toString().startsWith('private:') ||
        key.toString().startsWith('privatekey:') ||
        key.toString().startsWith('public:_') ||
        key.startsWith('_');
  }

  /// Verifies if the key is active, If key is active, return true; else false.
  bool _isActiveKey(AtMetaData? atMetaData) {
    // The legacy keys will not have metadata.
    // Returning true if metadata is null
    if (atMetaData == null) return true;
    var ttb = atMetaData.availableAt;
    var ttl = atMetaData.expiresAt;
    if (ttb == null && ttl == null) return true;
    var now = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (ttb != null) {
      var ttbMs = ttb.toUtc().millisecondsSinceEpoch;
      if (ttbMs > now) return false;
    }
    if (ttl != null) {
      var ttlMs = ttl.toUtc().millisecondsSinceEpoch;
      if (ttlMs < now) return false;
    }
    //If TTB or TTL populated but not met, return true.
    return true;
  }

  String? _prepareResponseData(String? operation, AtData? atData) {
    String? result;
    if (atData == null) {
      return result;
    }
    switch (operation) {
      case 'meta':
        result = json.encode(atData.metaData!.toJson());
        break;
      case 'all':
        result = json.encode(atData.toJson());
        break;
      default:
        result = atData.data;
        break;
    }
    return result;
  }

  Future<String?> getPrivateKey() async {
    var privateKeyData = await keyStore!.get(AT_PKAM_PRIVATE_KEY);
    return privateKeyData?.data;
  }

  Future<String>? getEncryptionPrivateKey() async {
    var privateKeyData = await keyStore!.get(AT_ENCRYPTION_PRIVATE_KEY);
    return privateKeyData?.data;
  }

  Future<String?> getPublicKey() async {
    var publicKeyData = await keyStore!.get(AT_PKAM_PUBLIC_KEY);
    return publicKeyData?.data;
  }

  Future<String?> getEncryptionPublicKey(String atSign) async {
    atSign = AtUtils.fixAtSign(atSign);
    var privateKeyData =
        await keyStore!.get('$AT_ENCRYPTION_PUBLIC_KEY$atSign');
    return privateKeyData?.data;
  }

  Future<String?> getEncryptionSelfKey() async {
    var selfKeyData = await keyStore!.get(AT_ENCRYPTION_SELF_KEY);
    return selfKeyData?.data;
  }

  ///Returns `true` on successfully storing the values into local secondary.
  Future<bool> putValue(String key, String value) async {
    dynamic isStored;
    var atData = AtData()..data = value;
    isStored = await keyStore!.put(key, atData);
    return isStored != null ? true : false;
  }
}
