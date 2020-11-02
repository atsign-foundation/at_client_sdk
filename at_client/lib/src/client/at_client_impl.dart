import 'dart:io';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/manager/preference_manager.dart';
import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/keystore/at_key.dart';
import 'package:base2e15/base2e15.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_utils.dart';
import 'package:at_commons/src/exception/at_exceptions.dart';
import 'package:at_persistence_secondary_server/src/utils/object_util.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart';

/// Implementation of [AtClient] interface
class AtClientImpl implements AtClient {
  AtClientPreference _preference;
  String currentAtSign;
  String _namespace;
  LocalSecondary _localSecondary;
  RemoteSecondary _remoteSecondary;

  var encryptionService;
  var logger = AtSignLogger('AtClientImpl');
  static final Map _atClientInstanceMap = <String, AtClient>{};

  /// Returns a new instance of [AtClient]. App has to pass the current user atSign
  /// and the client preference.
  static Future<AtClient> getClient(String currentAtSign) async {
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return _atClientInstanceMap[currentAtSign];
    }
    AtSignLogger('AtClientImpl')
        .severe('Instance of atclientimpl for $currentAtSign is not created');
    return null;
  }

  static void createClient(String currentAtSign, String namespace,
      AtClientPreference preferences) async {
    currentAtSign = AtUtils.formatAtSign(currentAtSign);
    if (preferences.isLocalStoreRequired) {
      var storageManager = StorageManager(preferences);
      await storageManager.init(currentAtSign, preferences.keyStoreSecret);
    }
    var atClientImpl = AtClientImpl(currentAtSign, namespace, preferences);
    await atClientImpl._init();
    atClientImpl.logger.info('AtClient init  done');
    _atClientInstanceMap[currentAtSign] = atClientImpl;
  }

  AtClientImpl(
      String _atSign, String namespace, AtClientPreference preference) {
    currentAtSign = AtUtils.formatAtSign(_atSign);
    _preference = preference;
    _namespace = namespace;
  }

  void _init() async {
    if (_preference.isLocalStoreRequired) {
      _localSecondary = LocalSecondary(currentAtSign, _preference);
    }
    _remoteSecondary = RemoteSecondary(currentAtSign, _preference,
        privateKey: _preference.privateKey);
    if (_preference.syncStrategy != null) {
      var syncManager = SyncManager.getInstance();
      syncManager.init(
          currentAtSign, _preference, _remoteSecondary, _localSecondary);
      await syncManager.sync();
    }
    encryptionService = EncryptionService();
    encryptionService.remoteSecondary = _remoteSecondary;
    encryptionService.currentAtSign = currentAtSign;
    encryptionService.localSecondary = _localSecondary;
  }

  Secondary getSecondary() {
    if (_preference.isLocalStoreRequired) {
      return _localSecondary;
    }
    return _remoteSecondary;
  }

  @override
  void startMonitor(String privateKey, Function acceptStream) async {
    await _remoteSecondary.monitor(MonitorVerbBuilder().buildCommand(),
        monitorCallBack, privateKey, acceptStream);
  }

  @override
  LocalSecondary getLocalSecondary() {
    return _localSecondary;
  }

  @override
  RemoteSecondary getRemoteSecondary() {
    return _remoteSecondary;
  }

  @override
  SyncManager getSyncManager() {
    return SyncManager.getInstance();
  }

  @override
  void setPreferences(AtClientPreference preference) async {
    var preferenceManager = PreferenceManager(preference);
    await preferenceManager.setPreferences();
  }

  Future<bool> persistPrivateKey(String privateKey) async {
    var atData = AtData();
    atData.data = privateKey.toString();
    await _localSecondary.keyStore.put(AT_PKAM_PRIVATE_KEY, atData);
    return true;
  }

  Future<bool> persistPublicKey(String publicKey) async {
    var atData = AtData();
    atData.data = publicKey.toString();
    await getLocalSecondary().keyStore.put(AT_PKAM_PUBLIC_KEY, atData);
    return true;
  }

  Future<String> getPrivateKey(String atSign) async {
    assert(atSign != null && atSign.isNotEmpty);
    var privateKeyData =
        await getLocalSecondary().keyStore.get(AT_PKAM_PRIVATE_KEY);
    var privateKey = privateKeyData?.data;
    return privateKey;
  }

  @override
  Future<bool> delete(AtKey atKey) {
    var isPublic = atKey.metadata != null ? atKey.metadata.isPublic : false;
    var isNamespaceAware =
        atKey.metadata != null ? atKey.metadata.namespaceAware : true;
    return _delete(atKey.key,
        sharedWith: atKey.sharedWith,
        isPublic: isPublic,
        namespaceAware: isNamespaceAware);
  }

  Future<bool> _delete(String key,
      {String sharedWith,
      bool isPublic = false,
      bool namespaceAware = true}) async {
    var keyWithNamespace;
    if (namespaceAware) {
      keyWithNamespace = _getKeyWithNamespace(key);
    } else {
      keyWithNamespace = key;
    }
    var builder = DeleteVerbBuilder()
      ..isPublic = isPublic
      ..sharedWith = sharedWith
      ..atKey = keyWithNamespace
      ..sharedBy = currentAtSign;
    var deleteResult = await getSecondary().executeVerb(builder);
    return deleteResult != null;
  }

  Future<dynamic> _get(String key,
      {String sharedWith,
      String sharedBy,
      bool isPublic = false,
      bool isCached = false,
      bool namespaceAware = true,
      String operation}) async {
    var builder;
    var keyWithNamespace;
    if (namespaceAware) {
      keyWithNamespace = _getKeyWithNamespace(key);
    } else {
      keyWithNamespace = key;
    }
    if (sharedBy != null && isCached) {
      builder = LLookupVerbBuilder()
        ..atKey = keyWithNamespace
        ..sharedBy = sharedBy
        ..isCached = isCached
        ..sharedWith = currentAtSign
        ..operation = operation;
      var encryptedResult = await getSecondary().executeVerb(builder);
      if (encryptedResult == 'data:null') {
        return null;
      }
      encryptedResult = _formatResult(encryptedResult);
      var encryptedResultMap = jsonDecode(encryptedResult);
      if (sharedBy != currentAtSign && operation == UPDATE_ALL) {
        //resultant value is encrypted. Decrypting to original value.
        var decryptedValue = await encryptionService.decrypt(
            encryptedResultMap['data'], sharedBy);
        encryptedResultMap['data'] = decryptedValue;
      }
      return encryptedResultMap;
    } else if (sharedBy != null && sharedBy != currentAtSign) {
      if (isPublic) {
        builder = PLookupVerbBuilder()
          ..atKey = keyWithNamespace
          ..sharedBy = sharedBy;
        if (operation != null) {
          builder.operation = operation;
        }
        var result = await getRemoteSecondary().executeVerb(builder);
        result = _formatResult(result);
        return jsonDecode(result);
      } else {
        builder = LookupVerbBuilder()
          ..atKey = keyWithNamespace
          ..sharedBy = sharedBy
          ..auth = true;
        if (operation != null) {
          builder.operation = operation;
        }
        var encryptedResult = await getRemoteSecondary().executeVerb(builder);
        // If lookup response from remote secondary is 'data:null'.
        if (encryptedResult != null && encryptedResult == 'data:null') {
          return null;
        }
        encryptedResult = _formatResult(encryptedResult);
        var encryptedResultMap = jsonDecode(encryptedResult);
        if (operation == UPDATE_ALL) {
          var decryptedValue;
          try {
            decryptedValue = await encryptionService.decrypt(
                encryptedResultMap['data'], sharedBy);
          } on KeyNotFoundException catch (e) {
            var errorCode = AtClientExceptionUtil.getErrorCode(e);
            return Future.error(AtClientException(errorCode,
                AtClientExceptionUtil.getErrorDescription(errorCode)));
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
        ..isPublic = isPublic
        ..sharedWith = sharedWith
        ..atKey = keyWithNamespace
        ..sharedBy = currentAtSign;
      if (operation != null) {
        builder.operation = operation;
      }
      if (sharedWith != currentAtSign) {
        var encryptedResult = await getSecondary().executeVerb(builder);

        if (encryptedResult != null && encryptedResult == 'data:null') {
          return null;
        }
        // If encrypted result is metadata decryption is not needed.
        encryptedResult = _formatResult(encryptedResult);
        var encryptedResultMap = jsonDecode(encryptedResult);
        if (operation == UPDATE_ALL) {
          var decryptedValue = await encryptionService.decryptLocal(
              encryptedResultMap['data'], currentAtSign, sharedWith);
          encryptedResultMap['data'] = decryptedValue;
        }
        return encryptedResultMap;
      }
    } else if (isPublic) {
      builder = LLookupVerbBuilder()
        ..atKey = 'public:' + keyWithNamespace
        ..sharedBy = currentAtSign;
    } else {
      builder = LLookupVerbBuilder()..atKey = keyWithNamespace;
      if (keyWithNamespace.startsWith(AT_PKAM_PRIVATE_KEY) ||
          keyWithNamespace.startsWith(AT_PKAM_PUBLIC_KEY)) {
        builder.sharedBy = null;
      } else {
        builder.sharedBy = currentAtSign;
      }
    }
    if (operation != null) {
      builder.operation = operation;
    }
    var result = await getSecondary().executeVerb(builder);
    result = _formatResult(result);
    return jsonDecode(result);
  }

  @override
  Future<AtValue> get(AtKey atKey) async {
    var isPublic = atKey.metadata != null ? atKey.metadata.isPublic : false;
    var namespaceAware =
        atKey.metadata != null ? atKey.metadata.namespaceAware : true;
    var isCached = atKey.metadata != null ? atKey.metadata.isCached : false;
    var getResult = await _get(atKey.key,
        sharedWith: AtUtils.formatAtSign(atKey.sharedWith),
        sharedBy: AtUtils.formatAtSign(atKey.sharedBy),
        isPublic: isPublic,
        isCached: isCached,
        namespaceAware: namespaceAware,
        operation: UPDATE_ALL);

    var atValue = AtValue();
    if (getResult == null || getResult == 'null') {
      return atValue;
    }
    if (atKey.metadata != null && atKey.metadata.isBinary) {
      atValue.value = Base2e15.decode(getResult['data']);
    } else {
      atValue.value = getResult['data'];
    }
    atValue.metadata = _prepareMetadata(getResult['metaData'], isPublic);
    return atValue;
  }

  @override
  Future<Metadata> getMeta(AtKey atKey) async {
    var isPublic = atKey.metadata != null ? atKey.metadata.isPublic : false;
    var namespaceAware =
        atKey.metadata != null ? atKey.metadata.namespaceAware : true;
    var isCached = atKey.metadata != null ? atKey.metadata.isCached : false;
    var getResult = await _get(atKey.key,
        sharedWith: atKey.sharedWith,
        sharedBy: atKey.sharedBy,
        isPublic: isPublic,
        isCached: isCached,
        namespaceAware: namespaceAware,
        operation: UPDATE_META);
    if (getResult == null || getResult == 'null') {
      return null;
    }
    return _prepareMetadata(getResult, isPublic);
  }

  Future<List<String>> getKeys(
      {String regex, String sharedBy, String sharedWith}) async {
    var builder = ScanVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = sharedBy
      ..regex = regex
      ..auth = true;
    var scanResult = await getSecondary().executeVerb(builder);
    scanResult = _formatResult(scanResult);
    var result = [];
    if (scanResult != null && scanResult.isNotEmpty) {
      result = List<String>.from(jsonDecode(scanResult));
    }
    return result;
  }

  @override
  Future<List<AtKey>> getAtKeys(
      {String regex, String sharedBy, String sharedWith}) async {
    var getKeysResult =
        await getKeys(regex: regex, sharedBy: sharedBy, sharedWith: sharedWith);
    var result = <AtKey>[];
    if (getKeysResult != null && getKeysResult.isNotEmpty) {
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

  Future<bool> _put(String key, String value,
      {String sharedWith, Metadata metadata}) async {
    var updateKey = key;
    if (metadata == null || (metadata != null && metadata.namespaceAware)) {
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
    if (value != null && sharedWith != null && sharedWith != currentAtSign) {
      try {
        builder.value = await encryptionService.encrypt(key, value, sharedWith);
      } on KeyNotFoundException catch (e) {
        var errorCode = AtClientExceptionUtil.getErrorCode(e);
        return Future.error(AtClientException(
            errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
      }
    }
    if (metadata != null) {
      builder.ttl = metadata.ttl;
      builder.ttb = metadata.ttb;
      builder.ttr = metadata.ttr;
      builder.ccd = metadata.ccd;
      builder.isBinary = metadata.isBinary;
      builder.isEncrypted = metadata.isEncrypted;
      builder.isPublic = metadata.isPublic;
      if (metadata.isHidden) {
        builder.atKey = '_' + updateKey;
      }
    }
    var isSyncRequired = true;
    if (updateKey.startsWith(AT_PKAM_PRIVATE_KEY) ||
        updateKey.startsWith(AT_PKAM_PUBLIC_KEY)) {
      builder.sharedBy = null;
    }
    if (SyncUtil.shouldSkipSync(updateKey)) {
      isSyncRequired = false;
    }
    var putResult;
    try {
      putResult =
          await getSecondary().executeVerb(builder, sync: isSyncRequired);
    } on AtClientException catch (e) {
      logger.severe(
          'error code: ${e.errorCode} error message: ${e.errorMessage}');
    } on Exception catch (e) {
      logger.severe('error in put: ${e.toString()}');
    }
    return putResult != null;
  }

  @override
  Future<bool> put(AtKey atKey, dynamic value) async {
    if (atKey.metadata != null && atKey.metadata.isBinary) {
      if (value != null && value.length > _preference.maxDataSize) {
        throw AtClientException('AT0005', 'BufferOverFlowException');
      }
      value = Base2e15.encode(value);
    }
    return _put(atKey.key, value,
        sharedWith: atKey.sharedWith, metadata: atKey.metadata);
  }

  @override
  Future<bool> notify(
      AtKey atKey, String value, OperationEnum operation) async {
    var notifyKey = atKey.key;
    var metadata = atKey.metadata;
    var sharedWith = atKey.sharedWith;
    if (metadata != null && metadata.namespaceAware) {
      notifyKey = _getKeyWithNamespace(atKey.key);
    }
    sharedWith = AtUtils.formatAtSign(sharedWith);
    var builder = NotifyVerbBuilder()
      ..atKey = notifyKey
      ..sharedBy = currentAtSign
      ..sharedWith = sharedWith
      ..value = value
      ..operation = operation;
    if (sharedWith != null && sharedWith != currentAtSign) {
      if (value != null) {
        try {
          builder.value =
              await encryptionService.encrypt(atKey.key, value, sharedWith);
        } on KeyNotFoundException catch (e) {
          var errorCode = AtClientExceptionUtil.getErrorCode(e);
          return Future.error(AtClientException(
              errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
        }
        print(builder.value);
      }
    }
    if (metadata != null) {
      builder.ttl = metadata.ttl;
      builder.ttb = metadata.ttb;
      builder.ttr = metadata.ttr;
      builder.ccd = metadata.ccd;
      builder.isPublic = metadata.isPublic;
    }
    var isSyncRequired = true;
    if (notifyKey.startsWith(AT_PKAM_PRIVATE_KEY) ||
        notifyKey.startsWith(AT_PKAM_PUBLIC_KEY)) {
      builder.sharedBy = null;
    }
    if (SyncUtil.shouldSkipSync(notifyKey)) {
      isSyncRequired = false;
    }
    var notifyResult =
        await getSecondary().executeVerb(builder, sync: isSyncRequired);
    return notifyResult != null;
  }

  @override
  Future<bool> putMeta(AtKey atKey) async {
    var updateKey = atKey.key;
    var metadata = atKey.metadata;
    if (metadata != null && metadata.namespaceAware) {
      updateKey = _getKeyWithNamespace(atKey.key);
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
      ..operation = UPDATE_META;

    var isSyncRequired = true;
    if (SyncUtil.shouldSkipSync(updateKey)) {
      isSyncRequired = false;
    }

    var updateMetaResult =
        await getSecondary().executeVerb(builder, sync: isSyncRequired);
    return updateMetaResult != null;
  }

  String _getKeyWithNamespace(String key) {
    var keyWithNamespace = key;
    if (_namespace != null && _namespace.isNotEmpty) {
      keyWithNamespace += '.${_namespace}';
    }
    return keyWithNamespace;
  }

  String getOperation(dynamic value, Metadata data) {
    if (value != null && data == null) {
      return VALUE;
    }
    // Verifies if any of the args are not null
    var isMetadataNotNull = ObjectsUtil.isAnyNotNull(
        a1: data.ttl,
        a2: data.ttb,
        a3: data.ttr,
        a4: data.ccd,
        a5: data.isBinary,
        a6: data.isEncrypted);
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

  String _formatResult(String commandResult) {
    var result = commandResult;
    if (result != null) {
      result = result.replaceFirst('data:', '');
    }
    return result;
  }

  Metadata _prepareMetadata(Map<String, dynamic> metadataMap, bool isPublic) {
    if (metadataMap == null) {
      return null;
    }
    var metadata = Metadata();
    metadata.expiresAt =
        (metadataMap['expiresAt'] != null && metadataMap['expiresAt'] != 'null')
            ? DateTime.parse(metadataMap['expiresAt'])
            : null;
    metadata.availableAt = (metadataMap['availableAt'] != null &&
            metadataMap['availableAt'] != 'null')
        ? DateTime.parse(metadataMap['availableAt'])
        : null;
    metadata.refreshAt =
        (metadataMap[REFRESH_AT] != null && metadataMap[REFRESH_AT] != 'null')
            ? DateTime.parse(metadataMap[REFRESH_AT])
            : null;
    metadata.ttr = metadataMap[AT_TTR];
    metadata.ttl = metadataMap[AT_TTL];
    metadata.ttb = metadataMap[AT_TTB];
    metadata.ccd = metadataMap[CCD];
    metadata.isBinary = metadataMap[IS_BINARY];
    metadata.isEncrypted = metadataMap[IS_ENCRYPTED];
    if (isPublic) {
      metadata.isPublic = isPublic;
    }
    return metadata;
  }

  Future<AtStreamResponse> stream(String sharedWith, String filePath) async {
    var streamResponse = AtStreamResponse();
    var streamId = Uuid().v4();
    var file = File(filePath);
    var data = file.readAsBytesSync();
    var fileName = basename(filePath);
    var command =
        "stream:init${sharedWith} ${streamId} '${fileName}' ${data.length}\n";
    var remoteSecondary = RemoteSecondary(currentAtSign, _preference);
    var result = await remoteSecondary.executeCommand(command, auth: true);
    logger.info('ack message:${result}');
    if (result != null && result.startsWith('stream:ack')) {
      result = result.replaceAll('stream:ack ', '');
      result = result.trim();
      logger.info('ack received for streamId:${streamId}');

      remoteSecondary.atLookUp.connection.getSocket().add(data);
      var streamResult = await remoteSecondary.atLookUp.messageListener
          .read(maxWaitMilliSeconds: _preference.outboundConnectionTimeout);
      if (streamResult != null && streamResult.startsWith('stream:done')) {
        await remoteSecondary.atLookUp.connection.close();
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

  void monitorCallBack(var response, Function acceptStream) async {
    logger.info(response);
    response = response.replaceFirst('notification:', '');
    var responseJson = jsonDecode(response);
    var notificationKey = responseJson['key'];
    var valueObject = responseJson['value'];
    var streamId = valueObject.split(':')[0];
    var fileName = valueObject.split(':')[1];
    var fileLength = valueObject.split(':')[2];
    var atKey = notificationKey.split(':')[1];
    var fromAtSign = responseJson['from'];
    fileName = fileName.replaceAll("'", '');
    atKey = atKey.replaceFirst(fromAtSign, '');
    atKey = atKey.trim();
    print('atKey: ${atKey}');
    if (atKey == 'stream_id') {
      // send in-app notification to receiver
      bool userResponse = await acceptStream(fromAtSign, fileName, fileLength);
      if (userResponse == true) {
        var handler = StreamNotificationHandler();
        handler.remoteSecondary = getRemoteSecondary();
        handler.localSecondary = getLocalSecondary();
        handler.preference = _preference;
        var notification = AtStreamNotification()
          ..streamId = streamId
          ..fileName = fileName
          ..currentAtSign = currentAtSign
          ..senderAtSign = fromAtSign
          ..fileLength = int.parse(fileLength);
        logger.info('Sending ack for stream notification:${notification}');
        await handler.streamAck(notification);
      }
    } else {
      logger.info('Non stream notification received. Ignoring');
    }
  }
}
