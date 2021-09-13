import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/manager/sync_manager_impl.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/service/file_transfer_service.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/src/utils/object_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

/// Implementation of [AtClient] interface
class AtClientImpl implements AtClient {
  AtClientPreference? _preference;

  AtClientPreference? get preference => _preference;
  String? currentAtSign;
  String? _namespace;
  LocalSecondary? _localSecondary;
  RemoteSecondary? _remoteSecondary;
  EncryptionService? _encryptionService;

  @override
  EncryptionService? get encryptionService => _encryptionService;

  final _logger = AtSignLogger('AtClientImpl');
  static final Map _atClientInstanceMap = <String, AtClient>{};

  /// Returns a new instance of [AtClient]. App has to pass the current user atSign
  /// and the client preference.
  @deprecated
  static Future<AtClient?> getClient(String? currentAtSign) async {
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return _atClientInstanceMap[currentAtSign];
    }
    AtSignLogger('AtClientImpl').severe('Instance of atclientimpl for $currentAtSign is not created');
    return null;
  }

  @deprecated

  /// use [create]
  static Future<void> createClient(String currentAtSign, String? namespace, AtClientPreference preferences) async {
    currentAtSign = AtUtils.formatAtSign(currentAtSign)!;
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return;
    }
    if (preferences.isLocalStoreRequired) {
      var storageManager = StorageManager(preferences);
      await storageManager.init(currentAtSign, preferences.keyStoreSecret);
    }
    var atClientImpl = AtClientImpl(currentAtSign, namespace, preferences);
    await atClientImpl._init();
    _atClientInstanceMap[currentAtSign] = atClientImpl;
  }

  /// use [create]
  AtClientImpl(String _atSign, String? namespace, AtClientPreference preference) {
    currentAtSign = AtUtils.formatAtSign(_atSign);
    _preference = preference;
    _namespace = namespace;
  }

  static Future<AtClient> create(String currentAtSign, String? namespace, AtClientPreference preferences) async {
    currentAtSign = AtUtils.formatAtSign(currentAtSign)!;
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return _atClientInstanceMap[currentAtSign];
    }
    if (preferences.isLocalStoreRequired) {
      var storageManager = StorageManager(preferences);
      await storageManager.init(currentAtSign, preferences.keyStoreSecret);
    }
    var atClientImpl = AtClientImpl._(currentAtSign, namespace, preferences);
    await atClientImpl._init();
    _atClientInstanceMap[currentAtSign] = atClientImpl;
    return _atClientInstanceMap[currentAtSign];
  }

  AtClientImpl._(String _atSign, String? namespace, AtClientPreference preference) {
    currentAtSign = AtUtils.formatAtSign(_atSign);
    _preference = preference;
    _namespace = namespace;
  }

  Future<void> _init() async {
    if (_preference!.isLocalStoreRequired) {
      _localSecondary = LocalSecondary(this);
    }
    _remoteSecondary = RemoteSecondary(currentAtSign!, _preference!, privateKey: _preference!.privateKey);
    _encryptionService = EncryptionService();
    _encryptionService!.remoteSecondary = _remoteSecondary;
    _encryptionService!.currentAtSign = currentAtSign;
    _encryptionService!.localSecondary = _localSecondary;
  }

  Secondary getSecondary({bool isDedicated = false}) {
    if (_preference!.isLocalStoreRequired) {
      return _localSecondary!;
    }
    if (isDedicated) {
      return RemoteSecondary(currentAtSign!, _preference!, privateKey: _preference!.privateKey);
    }
    return _remoteSecondary!;
  }

  @override
  Future<void> startMonitor(String privateKey, Function? notificationCallback, {String? regex}) async {
    var monitorVerbBuilder = MonitorVerbBuilder();
    if (regex != null) {
      monitorVerbBuilder.regex = regex;
    }
    await _remoteSecondary!.monitor(monitorVerbBuilder.buildCommand(), notificationCallback, privateKey);
  }

  @override
  LocalSecondary? getLocalSecondary() {
    return _localSecondary;
  }

  @override
  RemoteSecondary? getRemoteSecondary({bool isDedicated = false}) {
    if (isDedicated) {
      var remoteSecondary = RemoteSecondary(currentAtSign!, _preference!, privateKey: _preference!.privateKey);
      return remoteSecondary;
    }
    return _remoteSecondary;
  }

  @override
  @deprecated
  SyncManager? getSyncManager() {
    return SyncManagerImpl.getInstance().getSyncManager(currentAtSign);
  }

  @override
  void setPreferences(AtClientPreference preference) async {
    _preference = preference;
  }

  Future<bool> persistPrivateKey(String privateKey) async {
    var atData = AtData();
    atData.data = privateKey.toString();
    await _localSecondary!.keyStore!.put(AT_PKAM_PRIVATE_KEY, atData);
    return true;
  }

  Future<bool> persistPublicKey(String publicKey) async {
    var atData = AtData();
    atData.data = publicKey.toString();
    await getLocalSecondary()!.keyStore!.put(AT_PKAM_PUBLIC_KEY, atData);
    return true;
  }

  Future<String?> getPrivateKey(String atSign) async {
    var privateKeyData = await getLocalSecondary()!.keyStore!.get(AT_PKAM_PRIVATE_KEY);
    var privateKey = privateKeyData?.data;
    return privateKey;
  }

  @override
  Future<bool> delete(AtKey atKey, {bool isDedicated = false}) {
    var isPublic = atKey.metadata != null ? atKey.metadata!.isPublic! : false;
    var isCached = atKey.metadata != null ? atKey.metadata!.isCached : false;
    var isNamespaceAware = atKey.metadata != null ? atKey.metadata!.namespaceAware : true;
    return _delete(atKey.key!,
        sharedWith: atKey.sharedWith,
        sharedBy: atKey.sharedBy,
        isPublic: isPublic,
        isCached: isCached,
        namespaceAware: isNamespaceAware,
        isDedicated: isDedicated);
  }

  Future<bool> _delete(String key,
      {String? sharedWith,
      String? sharedBy,
      bool isPublic = false,
      bool isCached = false,
      bool namespaceAware = true,
      bool isDedicated = false}) async {
    var keyWithNamespace;
    if (namespaceAware) {
      keyWithNamespace = _getKeyWithNamespace(key);
    } else {
      keyWithNamespace = key;
    }
    sharedBy ??= currentAtSign;
    var builder = DeleteVerbBuilder()
      ..isCached = isCached
      ..isPublic = isPublic
      ..sharedWith = sharedWith
      ..atKey = keyWithNamespace
      ..sharedBy = sharedBy;
    var deleteResult =
        await getSecondary(isDedicated: isDedicated).executeVerb(builder, sync: (isDedicated ? false : null));
    return deleteResult != null;
  }

  Future<dynamic> _get(String key,
      {String? sharedWith,
      String? sharedBy,
      bool? isPublic = false,
      bool isCached = false,
      bool namespaceAware = true,
      String? operation,
      bool isDedicated = false}) async {
    var builder;
    var keyWithNamespace;
    if (namespaceAware) {
      keyWithNamespace = _getKeyWithNamespace(key);
    } else {
      keyWithNamespace = key;
    }
    if (sharedBy != null && isCached && !isPublic!) {
      builder = LLookupVerbBuilder()
        ..atKey = keyWithNamespace
        ..sharedBy = sharedBy
        ..isCached = isCached
        ..sharedWith = currentAtSign
        ..operation = operation;
      var secondary = getSecondary(isDedicated: isDedicated);
      var encryptedResult = await secondary.executeVerb(builder, sync: (isDedicated ? false : null));
      if (isDedicated && (secondary is RemoteSecondary)) {
        await secondary.atLookUp.connection!.close();
      }
      if (encryptedResult == 'data:null') {
        return null;
      }
      encryptedResult = _formatResult(encryptedResult);
      var encryptedResultMap = jsonDecode(encryptedResult!);
      if (operation == UPDATE_META) {
        return encryptedResultMap;
      }
      if (sharedBy != currentAtSign && operation == UPDATE_ALL) {
        //resultant value is encrypted. Decrypting to original value.
        try {
          var decryptedValue = await _encryptionService!.decrypt(encryptedResultMap['data'], sharedBy);
          encryptedResultMap['data'] = decryptedValue;
        } on Error catch (e) {
          _logger.severe('decryption error for command ${builder.buildCommand()}: $e');
        }
      } else {
        //resultant value is encrypted. Decrypting to original value.
        var isEncrypted = encryptedResultMap['metaData']['isEncrypted'];
        isEncrypted ??= false;
        var decryptedValue = await _encryptionService!.decryptForSelf(encryptedResultMap['data'], isEncrypted);
        encryptedResultMap['data'] = decryptedValue;
      }
      return encryptedResultMap;
    } else if (sharedBy != null && sharedBy != currentAtSign && !isCached) {
      if (isPublic!) {
        builder = PLookupVerbBuilder()
          ..atKey = keyWithNamespace
          ..sharedBy = sharedBy;
        if (operation != null) {
          builder.operation = operation;
        }
        var remoteSecondary = getRemoteSecondary(isDedicated: isDedicated);
        var result = await remoteSecondary!.executeVerb(builder, sync: (isDedicated ? false : null));
        if (isDedicated) {
          await remoteSecondary.atLookUp.connection!.close();
        }
        result = _formatResult(result)!;
        return jsonDecode(result);
      } else {
        builder = LookupVerbBuilder()
          ..atKey = keyWithNamespace
          ..sharedBy = sharedBy
          ..auth = true;
        if (operation != null) {
          builder.operation = operation;
        }
        var remoteSecondary = getRemoteSecondary(isDedicated: isDedicated);
        var encryptedResult = await remoteSecondary!.executeVerb(builder, sync: (isDedicated ? false : null));
        if (isDedicated) {
          await remoteSecondary.atLookUp.connection!.close();
        }
        // If lookup response from remote secondary is 'data:null'.
        if (encryptedResult == 'data:null') {
          return null;
        }
        encryptedResult = _formatResult(encryptedResult)!;
        var encryptedResultMap = jsonDecode(encryptedResult);
        if (operation == UPDATE_ALL) {
          var decryptedValue;
          try {
            decryptedValue = await _encryptionService!.decrypt(encryptedResultMap['data'], sharedBy);
          } on KeyNotFoundException catch (e) {
            var errorCode = AtClientExceptionUtil.getErrorCode(e);
            return Future.error(AtClientException(errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
          }
          encryptedResultMap['data'] = decryptedValue;
        }
        return encryptedResultMap;
      }
      // plookup and lookup can be executed only on remote
    } else if (sharedWith != null) {
      sharedWith = AtUtils.formatAtSign(sharedWith);
      builder = LLookupVerbBuilder()
        ..isCached = isCached
        ..isPublic = isPublic!
        ..sharedWith = sharedWith
        ..atKey = keyWithNamespace
        ..sharedBy = currentAtSign;
      if (operation != null) {
        builder.operation = operation;
      }
      if (sharedWith != currentAtSign) {
        var secondary = getSecondary(isDedicated: isDedicated);
        var encryptedResult = await secondary.executeVerb(builder, sync: (isDedicated ? false : null));
        if (isDedicated && (secondary is RemoteSecondary)) {
          await secondary.atLookUp.connection!.close();
        }
        if (encryptedResult != null && encryptedResult == 'data:null') {
          return null;
        }
        // If encrypted result is metadata decryption is not needed.
        encryptedResult = _formatResult(encryptedResult);
        var encryptedResultMap = jsonDecode(encryptedResult!);
        if (operation == UPDATE_ALL) {
          try {
            var decryptedValue =
                await _encryptionService!.decryptLocal(encryptedResultMap['data'], currentAtSign, sharedWith!);
            encryptedResultMap['data'] = decryptedValue;
          } on Exception catch (e) {
            _logger.severe('decryption exception for command ${builder.buildCommand()}: ${e.toString}');
          } on Error catch (e) {
            _logger.severe('decryption error for command ${builder.buildCommand()}: $e');
          }
        }
        return encryptedResultMap;
      }
    } else if (isPublic!) {
      builder = LLookupVerbBuilder()
        ..isCached = isCached
        ..atKey = 'public:' + keyWithNamespace;
      builder.sharedBy = sharedBy ?? currentAtSign;
    } else {
      builder = LLookupVerbBuilder()..atKey = keyWithNamespace;
      if (keyWithNamespace.startsWith(AT_PKAM_PRIVATE_KEY) || keyWithNamespace.startsWith(AT_PKAM_PUBLIC_KEY)) {
        builder.sharedBy = null;
      } else {
        builder.sharedBy = currentAtSign;
      }
    }
    if (operation != null) {
      builder.operation = operation;
    }
    var secondary = getSecondary(isDedicated: isDedicated);
    var result = await secondary.executeVerb(builder, sync: (isDedicated ? false : null));
    if (isDedicated && (secondary is RemoteSecondary)) {
      await secondary.atLookUp.connection!.close();
    }
    if (result == null || result == 'data:null') {
      return null;
    }
    result = _formatResult(result);
    var encryptedResultMap = jsonDecode(result!);
    //If operation is update_meta, return metadata.
    if (operation == UPDATE_META) {
      return encryptedResultMap;
    }
    var isEncrypted = encryptedResultMap['metaData']['isEncrypted'];
    isEncrypted ??= false;
    var decryptedValue = await _encryptionService!.decryptForSelf(encryptedResultMap['data'], isEncrypted);
    encryptedResultMap['data'] = decryptedValue;
    return encryptedResultMap;
  }

  @override
  Future<AtValue> get(AtKey atKey, {bool isDedicated = false}) async {
    var isPublic = atKey.metadata != null ? atKey.metadata!.isPublic : false;
    var namespaceAware = atKey.metadata != null ? atKey.metadata!.namespaceAware : true;
    var isCached = atKey.metadata != null ? atKey.metadata!.isCached : false;
    var getResult = await _get(atKey.key!,
        sharedWith: AtUtils.formatAtSign(atKey.sharedWith),
        sharedBy: AtUtils.formatAtSign(atKey.sharedBy),
        isPublic: isPublic,
        isCached: isCached,
        namespaceAware: namespaceAware,
        operation: UPDATE_ALL,
        isDedicated: isDedicated);

    var atValue = AtValue();
    if (getResult == null || getResult == 'null') {
      return atValue;
    }
    if (atKey.metadata != null && atKey.metadata!.isBinary!) {
      atValue.value = Base2e15.decode(getResult['data']);
    } else {
      atValue.value = getResult['data'];
      if (atValue.value is String) {
        atValue.value = VerbUtil.getFormattedValue(atValue.value);
      }
    }
    atValue.metadata = _prepareMetadata(getResult['metaData'], isPublic);
    return atValue;
  }

  @override
  Future<Metadata?> getMeta(AtKey atKey, {bool isDedicated = false}) async {
    var isPublic = atKey.metadata != null ? atKey.metadata!.isPublic : false;
    var namespaceAware = atKey.metadata != null ? atKey.metadata!.namespaceAware : true;
    var isCached = atKey.metadata != null ? atKey.metadata!.isCached : false;
    var getResult = await _get(atKey.key!,
        sharedWith: atKey.sharedWith,
        sharedBy: atKey.sharedBy,
        isPublic: isPublic,
        isCached: isCached,
        namespaceAware: namespaceAware,
        operation: UPDATE_META,
        isDedicated: isDedicated);
    if (getResult == null || getResult == 'null') {
      return null;
    }
    return _prepareMetadata(getResult, isPublic);
  }

  @override
  Future<List<String>> getKeys({String? regex, String? sharedBy, String? sharedWith, bool isDedicated = false}) async {
    var builder = ScanVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = sharedBy
      ..regex = regex
      ..auth = true;
    var secondary = getSecondary(isDedicated: isDedicated);
    var scanResult = await secondary.executeVerb(builder);
    if (isDedicated && (secondary is RemoteSecondary)) {
      await secondary.atLookUp.connection!.close();
    }
    scanResult = _formatResult(scanResult);
    var result = [];
    if (scanResult != null && scanResult.isNotEmpty) {
      result = List<String>.from(jsonDecode(scanResult));
    }
    return result as FutureOr<List<String>>;
  }

  @override
  Future<List<AtKey>> getAtKeys({String? regex, String? sharedBy, String? sharedWith, bool isDedicated = false}) async {
    var getKeysResult =
        await getKeys(regex: regex, sharedBy: sharedBy, sharedWith: sharedWith, isDedicated: isDedicated);
    var result = <AtKey>[];
    if (getKeysResult.isNotEmpty) {
      getKeysResult.forEach((key) {
        result.add(AtKey.fromString(key));
      });
    }
    return result;
  }

//  @override
//  Future<bool> putBinary(String key, List<int> value,
//      {String sharedWith, Metadata metadata}) async {
//    if (value != null && value.length > _preference.maxDataSize) {
//      throw AtClientException('AT0005', 'BufferOverFlowException');
//    }
//    var encodedValue = Base2e15.encode(value);
//    return await put(key, encodedValue,
//        sharedWith: sharedWith, metadata: metadata);
//  }
//
//  @override
//  Future<bool> putBinaryAtKey(AtKey key, List<int> value,
//      {Metadata metadata}) async {
//    if (value != null && value.length > _preference.maxDataSize) {
//      throw AtClientException('AT0005', 'BufferOverFlowException');
//    }
//    var encodedValue = Base2e15.encode(value);
//    return await put(key.key, encodedValue,
//        sharedWith: key.sharedWith, metadata: metadata);
//  }

  Future<bool> _put(String key, dynamic value,
      {String? sharedWith, Metadata? metadata, bool isDedicated = false}) async {
    var updateKey = key;
    if (metadata == null || metadata.namespaceAware) {
      updateKey = _getKeyWithNamespace(key);
    }
    var operation = getOperation(value, metadata);
    sharedWith = AtUtils.formatAtSign(sharedWith);
    var builder = UpdateVerbBuilder()
      ..atKey = updateKey
      ..sharedBy = currentAtSign
      ..sharedWith = sharedWith
      ..value = value
      ..operation = operation;

    if (metadata != null) {
      builder.ttl = metadata.ttl;
      builder.ttb = metadata.ttb;
      builder.ttr = metadata.ttr;
      builder.ccd = metadata.ccd;
      builder.isBinary = metadata.isBinary;
      builder.isEncrypted = metadata.isEncrypted;
      builder.isPublic = metadata.isPublic!;
      if (metadata.isHidden) {
        builder.atKey = '_' + updateKey;
      }
    }
    if (value != null) {
      if (sharedWith != null && sharedWith != currentAtSign) {
        try {
          builder.value = await _encryptionService!.encrypt(key, value, sharedWith);
        } on KeyNotFoundException catch (e) {
          var errorCode = AtClientExceptionUtil.getErrorCode(e);
          return Future.error(AtClientException(errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
        }
      } else if (!builder.isPublic && !builder.atKey.toString().startsWith('_')) {
        builder.value = await _encryptionService!.encryptForSelf(key, value);
        builder.isEncrypted = true;
      }
    }
    var isSyncRequired;
    if (updateKey.startsWith(AT_PKAM_PRIVATE_KEY) || updateKey.startsWith(AT_PKAM_PUBLIC_KEY)) {
      builder.sharedBy = null;
    }
    if (SyncUtil.shouldSkipSync(updateKey)) {
      isSyncRequired = false;
    }
    //sign public data with private encryption key
    if (metadata != null && metadata.isPublic!) {
      try {
        var encryptionPrivateKey = await _localSecondary!.getEncryptionPrivateKey();
        if (encryptionPrivateKey != null) {
          _logger.finer('signing public data for key:$key');
          builder.dataSignature = _encryptionService!.signPublicData(encryptionPrivateKey, value);
        }
      } on Exception catch (e) {
        _logger.severe('Exception trying to sign public data:${e.toString()}');
      }
    }

    var putResult;
    try {
      if (builder.dataSignature != null) {
        builder.isJson = true;
      }
      var secondary = getSecondary(isDedicated: isDedicated);
      putResult = await secondary.executeVerb(builder, sync: (isDedicated ? false : isSyncRequired));
      if (isDedicated && (secondary is RemoteSecondary)) {
        await secondary.atLookUp.connection!.close();
      }
    } on AtClientException catch (e) {
      _logger.severe('error code: ${e.errorCode} error message: ${e.errorMessage}');
    } on Exception catch (e) {
      _logger.severe('error in put: ${e.toString()}');
    }
    return putResult != null;
  }

  @override
  Future<bool> put(AtKey atKey, dynamic value, {bool isDedicated = false}) async {
    if (atKey.metadata != null && atKey.metadata!.isBinary!) {
      if (value != null && value.length > _preference!.maxDataSize) {
        throw AtClientException('AT0005', 'BufferOverFlowException');
      }
      value = Base2e15.encode(value);
    }
    return _put(atKey.key!, value, sharedWith: atKey.sharedWith, metadata: atKey.metadata, isDedicated: isDedicated);
  }

  @override
  Future<bool> notify(AtKey atKey, String value, OperationEnum operation,
      {MessageTypeEnum? messageType,
      PriorityEnum? priority,
      StrategyEnum? strategy,
      int? latestN,
      String? notifier = SYSTEM,
      bool isDedicated = false}) async {
    var notifyKey = atKey.key;
    var metadata = atKey.metadata;
    var sharedWith = atKey.sharedWith;
    if (metadata != null && metadata.namespaceAware) {
      notifyKey = _getKeyWithNamespace(atKey.key!);
    }
    sharedWith = AtUtils.formatAtSign(sharedWith);
    var builder = NotifyVerbBuilder()
      ..atKey = notifyKey
      ..sharedBy = currentAtSign
      ..sharedWith = sharedWith
      ..value = value
      ..operation = operation
      ..messageType = messageType
      ..priority = priority
      ..strategy = strategy
      ..latestN = latestN
      ..notifier = notifier!;
    if (sharedWith != null && sharedWith != currentAtSign) {
      try {
        builder.value = await _encryptionService!.encrypt(atKey.key, value, sharedWith);
      } on KeyNotFoundException catch (e) {
        var errorCode = AtClientExceptionUtil.getErrorCode(e);
        return Future.error(AtClientException(errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
      }
    } else {
      builder.value = await _encryptionService!.encryptForSelf(atKey.key, value);
    }
    if (metadata != null) {
      builder.ttl = metadata.ttl;
      builder.ttb = metadata.ttb;
      builder.ttr = metadata.ttr;
      builder.ccd = metadata.ccd;
      builder.isPublic = metadata.isPublic!;
    }
    var isSyncRequired = true;
    if (notifyKey!.startsWith(AT_PKAM_PRIVATE_KEY) || notifyKey.startsWith(AT_PKAM_PUBLIC_KEY)) {
      builder.sharedBy = null;
    }
    if (SyncUtil.shouldSkipSync(notifyKey)) {
      isSyncRequired = false;
    }
    var secondary = getSecondary(isDedicated: isDedicated);
    if (isDedicated) {
      isSyncRequired = false;
    }
    var notifyResult = await getRemoteSecondary()?.executeVerb(builder, sync: (isDedicated ? false : isSyncRequired));
    if (isDedicated && (secondary is RemoteSecondary)) {
      await secondary.atLookUp.connection!.close();
    }
    return notifyResult != null;
  }

  @override
  Future<String> notifyAll(AtKey atKey, String value, OperationEnum operation, {bool isDedicated = false}) async {
    var returnMap = {};
    var sharedWithList = jsonDecode(atKey.sharedWith!);
    for (var sharedWith in sharedWithList) {
      atKey.sharedWith = sharedWith;
      var result = await notify(atKey, value, operation, isDedicated: isDedicated);
      returnMap.putIfAbsent(sharedWith, () => result);
    }
    return jsonEncode(returnMap);
  }

  @override
  Future<String> notifyStatus(String notificationId) async {
    var builder = NotifyStatusVerbBuilder()..notificationId = notificationId;
    var notifyStatus = await getRemoteSecondary()!.executeVerb(builder);
    return notifyStatus;
  }

  @override
  Future<String> notifyList({String? fromDate, String? toDate, String? regex, bool isDedicated = false}) async {
    try {
      var builder = NotifyListVerbBuilder()
        ..fromDate = fromDate
        ..toDate = toDate
        ..regex = regex;
      var remoteSecondary = getRemoteSecondary(isDedicated: isDedicated);
      var notifyList = await remoteSecondary!.executeVerb(builder);
      if (isDedicated) {
        await remoteSecondary.atLookUp.connection!.close();
      }
      return notifyList;
    } on AtLookUpException catch (e) {
      throw AtClientException(e.errorCode, e.errorMessage);
    }
  }

  @override
  Future<bool> putMeta(AtKey atKey) async {
    var updateKey = atKey.key;
    var metadata = atKey.metadata!;
    if (metadata.namespaceAware) {
      updateKey = _getKeyWithNamespace(atKey.key!);
    }
    var sharedWith = atKey.sharedWith;
    var builder = UpdateVerbBuilder();
    builder
      ..atKey = updateKey
      ..sharedBy = currentAtSign
      ..sharedWith = sharedWith
      ..ttl = metadata.ttl
      ..ttb = metadata.ttb
      ..ttr = metadata.ttr
      ..ccd = metadata.ccd
      ..isBinary = metadata.isBinary
      ..isEncrypted = metadata.isEncrypted
      ..dataSignature = metadata.dataSignature
      ..operation = UPDATE_META;

    var isSyncRequired = true;
    if (SyncUtil.shouldSkipSync(updateKey!)) {
      isSyncRequired = false;
    }

    var updateMetaResult = await getSecondary().executeVerb(builder, sync: isSyncRequired);
    return updateMetaResult != null;
  }

  String _getKeyWithNamespace(String key) {
    var keyWithNamespace = key;
    if (_namespace != null && _namespace!.isNotEmpty) {
      keyWithNamespace = '$keyWithNamespace.$_namespace';
    }
    return keyWithNamespace;
  }

  String? getOperation(dynamic value, Metadata? data) {
    if (value != null && data == null) {
      return VALUE;
    }
    // Verifies if any of the args are not null
    var isMetadataNotNull = ObjectsUtil.isAnyNotNull(
        a1: data!.ttl, a2: data.ttb, a3: data.ttr, a4: data.ccd, a5: data.isBinary, a6: data.isEncrypted);
    //If value is not null and metadata is not null, return UPDATE_ALL
    if (value != null && isMetadataNotNull) {
      return UPDATE_ALL;
    }
    //If value is null and metadata is not null,
    if (value == null && isMetadataNotNull) {
      return UPDATE_META;
    }
    return null;
  }

  String? _formatResult(String? commandResult) {
    var result = commandResult;
    if (result != null) {
      result = result.replaceFirst('data:', '');
    }
    return result;
  }

  Metadata? _prepareMetadata(Map<String, dynamic>? metadataMap, bool? isPublic) {
    if (metadataMap == null) {
      return null;
    }
    var metadata = Metadata();
    metadata.expiresAt = (metadataMap['expiresAt'] != null && metadataMap['expiresAt'] != 'null')
        ? DateTime.parse(metadataMap['expiresAt'])
        : null;
    metadata.availableAt = (metadataMap['availableAt'] != null && metadataMap['availableAt'] != 'null')
        ? DateTime.parse(metadataMap['availableAt'])
        : null;
    metadata.refreshAt = (metadataMap[REFRESH_AT] != null && metadataMap[REFRESH_AT] != 'null')
        ? DateTime.parse(metadataMap[REFRESH_AT])
        : null;
    metadata.createdAt = (metadataMap[CREATED_AT] != null && metadataMap[CREATED_AT] != 'null')
        ? DateTime.parse(metadataMap[CREATED_AT])
        : null;
    metadata.updatedAt = (metadataMap[UPDATED_AT] != null && metadataMap[UPDATED_AT] != 'null')
        ? DateTime.parse(metadataMap[UPDATED_AT])
        : null;
    metadata.ttr = metadataMap[AT_TTR];
    metadata.ttl = metadataMap[AT_TTL];
    metadata.ttb = metadataMap[AT_TTB];
    metadata.ccd = metadataMap[CCD];
    metadata.isBinary = metadataMap[IS_BINARY];
    metadata.isEncrypted = metadataMap[IS_ENCRYPTED];
    metadata.dataSignature = metadataMap[PUBLIC_DATA_SIGNATURE];
    if (isPublic!) {
      metadata.isPublic = isPublic;
    }
    return metadata;
  }

  @override
  Future<AtStreamResponse> stream(String sharedWith, String filePath, {String? namespace}) async {
    var streamResponse = AtStreamResponse();
    var streamId = Uuid().v4();
    var file = File(filePath);
    var data = file.readAsBytesSync();
    var fileName = basename(filePath);
    fileName = base64.encode(utf8.encode(fileName));
    var encryptedData = await _encryptionService!.encryptStream(data, sharedWith);
    var command = 'stream:init$sharedWith namespace:$namespace $streamId $fileName ${encryptedData.length}\n';
    _logger.finer('sending stream init:$command');
    var remoteSecondary = RemoteSecondary(currentAtSign!, _preference!);
    var result = await remoteSecondary.executeCommand(command, auth: true);
    _logger.finer('ack message:$result');
    if (result != null && result.startsWith('stream:ack')) {
      result = result.replaceAll('stream:ack ', '');
      result = result.trim();
      _logger.finer('ack received for streamId:$streamId');
      remoteSecondary.atLookUp.connection!.getSocket().add(encryptedData);
      var streamResult = await remoteSecondary.atLookUp.messageListener
          .read(maxWaitMilliSeconds: _preference!.outboundConnectionTimeout);
      if (streamResult != null && streamResult.startsWith('stream:done')) {
        await remoteSecondary.atLookUp.connection!.close();
        streamResponse.status = AtStreamStatus.COMPLETE;
      }
    } else if (result != null && result.startsWith('error:')) {
      result = result.replaceAll('error:', '');
      streamResponse.errorCode = result.split('-')[0];
      streamResponse.errorMessage = result.split('-')[1];
      streamResponse.status = AtStreamStatus.ERROR;
    } else {
      streamResponse.status = AtStreamStatus.NO_ACK;
    }
    return streamResponse;
  }

  Future<void> sendStreamAck(String streamId, String fileName, int fileLength, String senderAtSign,
      Function streamCompletionCallBack, Function streamReceiveCallBack) async {
    var handler = StreamNotificationHandler();
    handler.remoteSecondary = getRemoteSecondary();
    handler.localSecondary = getLocalSecondary();
    handler.preference = _preference;
    handler.encryptionService = _encryptionService;
    var notification = AtStreamNotification()
      ..streamId = streamId
      ..fileName = fileName
      ..currentAtSign = currentAtSign!
      ..senderAtSign = senderAtSign
      ..fileLength = fileLength;
    _logger.info('Sending ack for stream notification:$notification');
    await handler.streamAck(notification, streamCompletionCallBack, streamReceiveCallBack);
  }

  @override
  Future<Map<String, FileTransferObject>> uploadFile(List<File> files, List<String> sharedWithAtSigns) async {
    var encryptionKey = _encryptionService!.generateFileEncryptionKey();
    var key = TextConstants.FILE_TRANSFER_KEY + Uuid().v4();
    var fileStatus = await _uploadFiles(key, files, encryptionKey);
    var fileUrl = TextConstants.FILEBIN_URL + 'archive/' + key + '/zip';
    return shareFiles(sharedWithAtSigns, key, fileUrl, encryptionKey, fileStatus);
  }

  @override
  Future<Map<String, FileTransferObject>> shareFiles(
      List<String> sharedWithAtSigns, String key, String fileUrl, String encryptionKey, List<FileStatus> fileStatus,
      {DateTime? date}) async {
    var result = <String, FileTransferObject>{};
    for (var sharedWithAtSign in sharedWithAtSigns) {
      var fileTransferObject =
          FileTransferObject(key, encryptionKey, fileUrl, sharedWithAtSign, fileStatus, date: date);
      try {
        var atKey = AtKey()
          ..key = key
          ..sharedWith = sharedWithAtSign
          ..metadata = Metadata()
          ..metadata!.ttr = -1
          ..sharedBy = currentAtSign;
        fileTransferObject.sharedStatus = await put(atKey, jsonEncode(fileTransferObject.toJson()));
      } on Exception catch (e) {
        fileTransferObject.sharedStatus = false;
        fileTransferObject.error = e.toString();
      }
      result[sharedWithAtSign] = fileTransferObject;
    }
    return result;
  }

  Future<List<FileStatus>> _uploadFiles(String transferId, List<File> files, String encryptionKey) async {
    var fileStatuses = <FileStatus>[];
    for (var file in files) {
      var fileStatus = FileStatus(
        fileName: file.path.split('/').last,
        isUploaded: false,
        size: await file.length(),
      );
      try {
        var encryptedFile = _encryptionService!.encryptFile(
          file.readAsBytesSync(),
          encryptionKey,
        );
        var response = await FileTransferService().uploadToFileBin(
          encryptedFile,
          transferId,
          fileStatus.fileName!,
        );
        if (response is http.Response && response.statusCode == 201) {
          Map fileInfo = jsonDecode(response.body);
          // changing file name if it's not url friendly
          fileStatus.fileName = fileInfo['file']['filename'];
          fileStatus.isUploaded = true;
        }

        // storing sent files in a a directory.
        if (preference?.downloadPath != null) {
          var sentFilesDirectory = await Directory(preference!.downloadPath! + '/sent-files').create();
          await File(file.path).copy(sentFilesDirectory.path + '/${fileStatus.fileName}');
        }
      } on Exception catch (e) {
        fileStatus.error = e.toString();
      }
      fileStatuses.add(fileStatus);
    }
    return fileStatuses;
  }

  @override
  Future<List<FileStatus>> reuploadFiles(List<File> files, FileTransferObject fileTransferObject) async {
    var response = await _uploadFiles(fileTransferObject.transferId, files, fileTransferObject.fileEncryptionKey);
    return response;
  }

  @override
  Future<List<File>> downloadFile(String transferId, String sharedByAtSign, {String? downloadPath}) async {
    downloadPath ??= preference!.downloadPath;
    if (downloadPath == null) {
      throw Exception('downloadPath not found');
    }
    var atKey = AtKey()
      ..key = transferId
      ..sharedBy = sharedByAtSign;
    var result = await get(atKey);
    late var fileTransferObject;
    try {
      fileTransferObject = FileTransferObject.fromJson(jsonDecode(result.value));
    } on Exception catch (e) {
      throw Exception('json decode exception in download file ${e.toString()}');
    }
    var downloadedFiles = <File>[];
    var fileDownloadReponse = await FileTransferService().downloadFromFileBin(fileTransferObject, downloadPath);
    if (fileDownloadReponse.isError) {
      throw Exception('download fail');
    }
    var encryptedFileList = Directory(fileDownloadReponse.filePath!).listSync();
    try {
      for (var encryptedFile in encryptedFileList) {
        var decryptedFile = _encryptionService!
            .decryptFile(File(encryptedFile.path).readAsBytesSync(), fileTransferObject.fileEncryptionKey);
        var downloadedFile = File(downloadPath + '/' + encryptedFile.path.split('/').last);
        downloadedFile.writeAsBytesSync(decryptedFile);
        downloadedFiles.add(downloadedFile);
      }
      // deleting temp directory
      Directory(fileDownloadReponse.filePath!).deleteSync(recursive: true);
      return downloadedFiles;
    } catch (e) {
      print('error in downloadFile: $e');
      return [];
    }
  }

  @deprecated
  Future<void> encryptUnEncryptedData() async {
    await _encryptionService!.encryptUnencryptedData();
  }

  @override
  String? getCurrentAtSign() {
    return currentAtSign;
  }

  @override
  AtClientPreference? getPreferences() {
    return _preference;
  }

  @override
  Future<String?> notifyChange(NotificationParams notificationParams) async {
    // Check for internet. Since notify invoke remote secondary directly, network connection
    // is mandatory.
    if (!await NetworkUtil.isNetworkAvailable()) {
      throw AtClientException(at_client_error_codes['AtClientException'], 'No network availability');
    }
    // validate sharedWith atSign
    AtUtils.fixAtSign(notificationParams.atKey.sharedWith!);
    // Check if sharedWith AtSign exists
    AtClientValidation.validateAtSign(notificationParams.atKey.sharedWith!, _preference!.rootDomain, _preference!.rootPort);
    // validate sharedBy atSign
    notificationParams.atKey.sharedBy ??= getCurrentAtSign();
    AtUtils.fixAtSign(notificationParams.atKey.sharedBy!);
    // validate atKey
    AtClientValidation.validateAtKey(notificationParams.atKey);
    // validate metadata
    // If namespaceAware is set to true, append nameSpace to key.
    if (notificationParams.atKey.metadata != null && notificationParams.atKey.metadata!.namespaceAware) {
      notificationParams.atKey.key = _getKeyWithNamespace(notificationParams.atKey.key!);
    }
    notificationParams.atKey.sharedBy ??= currentAtSign;

    var builder = NotifyVerbBuilder()
      ..atKey = notificationParams.atKey.key
      ..sharedBy = notificationParams.atKey.sharedBy
      ..sharedWith = notificationParams.atKey.sharedWith
      ..operation = notificationParams.operation
      ..messageType = notificationParams.messageType
      ..priority = notificationParams.priority
      ..strategy = notificationParams.strategy
      ..latestN = notificationParams.latestN
      ..notifier = notificationParams.notifier;

    // If value is not null, encrypt the value
    if (notificationParams.value != null && notificationParams.value!.isNotEmpty) {
      // If atKey is being notified to another atSign, encrypt data with other
      // atSign encryption public key.
      if (notificationParams.atKey.sharedWith != null && notificationParams.atKey.sharedWith != currentAtSign) {
        try {
          builder.value = await _encryptionService!
              .encrypt(notificationParams.atKey.key, notificationParams.value!, notificationParams.atKey.sharedWith!);
        } on KeyNotFoundException catch (e) {
          var errorCode = AtClientExceptionUtil.getErrorCode(e);
          return Future.error(AtClientException(errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
        }
      }
      // If sharedWith is currentAtSign, encrypt data with currentAtSign encryption public key.
      if (notificationParams.atKey.sharedWith == null || notificationParams.atKey.sharedWith == currentAtSign) {
        builder.value =
            await _encryptionService!.encryptForSelf(notificationParams.atKey.key, notificationParams.value!);
      }
    }
    // If metadata is not null, add metadata to notify builder object.
    if (notificationParams.atKey.metadata != null) {
      builder.ttl = notificationParams.atKey.metadata!.ttl;
      builder.ttb = notificationParams.atKey.metadata!.ttb;
      builder.ttr = notificationParams.atKey.metadata!.ttr;
      builder.ccd = notificationParams.atKey.metadata!.ccd;
      builder.isPublic = notificationParams.atKey.metadata!.isPublic!;
    }
    if (notificationParams.atKey.key!.startsWith(AT_PKAM_PRIVATE_KEY) ||
        notificationParams.atKey.key!.startsWith(AT_PKAM_PUBLIC_KEY)) {
      builder.sharedBy = null;
    }
    return await getRemoteSecondary()?.executeVerb(builder);
  }
}
