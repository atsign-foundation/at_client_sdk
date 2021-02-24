import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/BatchVerbBuilder.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/manager/preference_manager.dart';
import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/manager/sync_manager_impl.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_commons/src/exception/at_exceptions.dart';
import 'package:at_commons/src/keystore/at_key.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/outbound_connection.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/src/utils/object_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart';
import 'package:base2e15/base2e15.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
//import 'package:cron/cron.dart';

/// Implementation of [AtClient] interface
class AtClientImpl implements AtClient {
  AtClientPreference _preference;

  AtClientPreference get preference => _preference;
  String currentAtSign;
  String _namespace;
  LocalSecondary _localSecondary;
  RemoteSecondary _remoteSecondary;
  OutboundConnection _monitorConnection;

  EncryptionService encryptionService;
  var logger = AtSignLogger('AtClientImpl');
  static final Map _atClientInstanceMap = <String, AtClient>{};

  /// Returns a new instance of [AtClient]. App has to pass the current user atSign
  /// and the client preference.
  static Future<AtClient> getClient(String currentAtSign) async {
    print('currentAtSign : $currentAtSign, keys: ${_atClientInstanceMap.keys}');
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return _atClientInstanceMap[currentAtSign];
    }
    AtSignLogger('AtClientImpl')
        .severe('Instance of atclientimpl for $currentAtSign is not created');
  }

  static void createClient(String currentAtSign, String namespace,
      AtClientPreference preferences) async {
    currentAtSign = AtUtils.formatAtSign(currentAtSign);
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return;
    }
    if (preferences.isLocalStoreRequired) {
      var storageManager = StorageManager(preferences);
      await storageManager.init(currentAtSign, preferences.keyStoreSecret);
    }
    var atClientImpl = AtClientImpl(currentAtSign, namespace, preferences);
    await atClientImpl._init();
    atClientImpl.logger
        .info('AtClient init  done for : ${atClientImpl.currentAtSign}');
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
  Future<OutboundConnection> startMonitor(
      String privateKey, Function notificationCallback) async {
    return await _remoteSecondary.monitor(
        MonitorVerbBuilder().buildCommand(), notificationCallback, privateKey);
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
    return SyncManagerImpl.getInstance().getSyncManager(currentAtSign);
  }

  @override
  void setPreferences(AtClientPreference preference) async {
    var preferenceManager = PreferenceManager(preference, currentAtSign);
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
      if (operation == UPDATE_META) {
        return encryptedResultMap;
      }
      if (sharedBy != currentAtSign && operation == UPDATE_ALL) {
        //resultant value is encrypted. Decrypting to original value.
        var decryptedValue = await encryptionService.decrypt(
            encryptedResultMap['data'], sharedBy);
        encryptedResultMap['data'] = decryptedValue;
      } else {
        //resultant value is encrypted. Decrypting to original value.
        var isEncrypted = encryptedResultMap['metaData']['isEncrypted'];
        isEncrypted ??= false;
        var decryptedValue = await encryptionService.decryptForSelf(
            encryptedResultMap['data'], isEncrypted);
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
    if (result == null || result == 'data:null') {
      return null;
    }
    result = _formatResult(result);
    var encryptedResultMap = jsonDecode(result);
    //If operation is update_meta, return metadata.
    if (operation == UPDATE_META) {
      return encryptedResultMap;
    }
    var isEncrypted = encryptedResultMap['metaData']['isEncrypted'];
    isEncrypted ??= false;
    var decryptedValue = await encryptionService.decryptForSelf(
        encryptedResultMap['data'], isEncrypted);
    encryptedResultMap['data'] = decryptedValue;
    return encryptedResultMap;
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
      if (atValue.value is String) {
        atValue.value = VerbUtil.getFormattedValue(atValue.value);
      }
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

  Future<bool> _put(String key, dynamic value,
      {String sharedWith, Metadata metadata}) async {
    UpdateVerbBuilder builder = await prepareUpdateBuilder(key, value,
        sharedWith: sharedWith, metadata: metadata);

    var isSyncRequired;
    if (SyncUtil.shouldSkipSync(builder.atKey)) {
      isSyncRequired = false;
    }

    var putResult;
    try {
      if (builder.dataSignature != null) {
        builder.isJson = true;
      }
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
  Future<dynamic> runBatchCommand(List<VerbBuilder> atVerbBuilders) async {
    var batchRequests = _getBatchRequests(atVerbBuilders);
    var batchResponse = await _sendBatch(batchRequests);
    return batchResponse;
  }

  @override
  Future<bool> notify(AtKey atKey, String value, OperationEnum operation,
      {MessageTypeEnum messageType,
      PriorityEnum priority,
      StrategyEnum strategy,
      int latestN,
      String notifier}) async {
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
      ..operation = operation
      ..messageType = messageType
      ..priority = priority
      ..strategy = strategy
      ..latestN = latestN
      ..notifier = notifier;
    if (value != null) {
      if (sharedWith != null && sharedWith != currentAtSign) {
        try {
          builder.value =
              await encryptionService.encrypt(atKey.key, value, sharedWith);
        } on KeyNotFoundException catch (e) {
          var errorCode = AtClientExceptionUtil.getErrorCode(e);
          return Future.error(AtClientException(
              errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
        }
      } else {
        builder.value =
            await encryptionService.encryptForSelf(atKey.key, value);
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
  Future<String> notifyAll(
      AtKey atKey, String value, OperationEnum operation) async {
    var returnMap = {};
    var sharedWithList = jsonDecode(atKey.sharedWith);
    for (var sharedWith in sharedWithList) {
      atKey.sharedWith = sharedWith;
      var result = await notify(atKey, value, operation);
      returnMap.putIfAbsent(sharedWith, () => result);
    }
    return jsonEncode(returnMap);
  }

  @override
  Future<String> notifyStatus(String notificationId) async {
    var builder = NotifyStatusVerbBuilder()..notificationId = notificationId;
    var notifyStatus = await getRemoteSecondary().executeVerb(builder);
    return notifyStatus;
  }

  @override
  Future<String> notifyList(
      {String fromDate, String toDate, String regex}) async {
    try {
      var builder = NotifyListVerbBuilder()
        ..fromDate = fromDate
        ..toDate = toDate
        ..regex = regex;
      var notifyList = await getRemoteSecondary().executeVerb(builder);
      return notifyList;
    } on AtLookUpException catch (e) {
      throw AtClientException(e.errorCode, e.errorMessage);
    }
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
      ..dataSignature = metadata.dataSignature
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
    metadata.createdAt =
        (metadataMap[CREATED_AT] != null && metadataMap[CREATED_AT] != 'null')
            ? DateTime.parse(metadataMap[CREATED_AT])
            : null;
    metadata.updatedAt =
        (metadataMap[UPDATED_AT] != null && metadataMap[UPDATED_AT] != 'null')
            ? DateTime.parse(metadataMap[UPDATED_AT])
            : null;
    metadata.ttr = metadataMap[AT_TTR];
    metadata.ttl = metadataMap[AT_TTL];
    metadata.ttb = metadataMap[AT_TTB];
    metadata.ccd = metadataMap[CCD];
    metadata.isBinary = metadataMap[IS_BINARY];
    metadata.isEncrypted = metadataMap[IS_ENCRYPTED];
    metadata.dataSignature = metadataMap[PUBLIC_DATA_SIGNATURE];
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
    fileName = base64.encode(utf8.encode(fileName));
    var command =
        'stream:init${sharedWith} ${streamId} ${fileName} ${data.length}\n';
    logger.finer('sending stream init:${command}');
    var remoteSecondary = RemoteSecondary(currentAtSign, _preference);
    var result = await remoteSecondary.executeCommand(command, auth: true);
    logger.finer('ack message:${result}');
    if (result != null && result.startsWith('stream:ack')) {
      result = result.replaceAll('stream:ack ', '');
      result = result.trim();
      logger.finer('ack received for streamId:${streamId}');

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

  Future<void> sendStreamAck(
      String streamId,
      String fileName,
      int fileLength,
      String senderAtSign,
      Function streamCompletionCallBack,
      Function streamReceiveCallBack) async {
    var handler = StreamNotificationHandler();
    handler.remoteSecondary = getRemoteSecondary();
    handler.localSecondary = getLocalSecondary();
    handler.preference = _preference;
    var notification = AtStreamNotification()
      ..streamId = streamId
      ..fileName = fileName
      ..currentAtSign = currentAtSign
      ..senderAtSign = senderAtSign
      ..fileLength = fileLength;
    logger.info('Sending ack for stream notification:${notification}');
    await handler.streamAck(
        notification, streamCompletionCallBack, streamReceiveCallBack);
  }

  Future<void> encryptUnEncryptedData() async {
    await encryptionService.encryptUnencryptedData();
  }

  dynamic _sendBatch(List<BatchRequest> requests) async {
    var command = 'batch:';
    command += jsonEncode(requests);
    command += '\n';
    var verbResult = await _remoteSecondary.executeCommand(command, auth: true);
    logger.finer('batch result:$verbResult');
    if (verbResult != null) {
      verbResult = verbResult.replaceFirst('data:', '');
    }
    return jsonDecode(verbResult);
  }

  dynamic _runBatch(List<VerbBuilder> requests) async {
    var batchResponse = Map();
    List<BatchRequest> batchRequests = [];
    var id = 0;
    for (var request in requests) {
      var verbResult;
      if ((request is UpdateVerbBuilder) || (request is DeleteVerbBuilder)) {
        verbResult = await _localSecondary.executeVerb(request);
      } else {
        verbResult = await _localSecondary.executeVerb(request);
        if ((verbResult == null) || (verbResult == 'data:null')) {
          var batchRequest = BatchRequest(id, request.buildCommand());
          batchRequests.add(batchRequest);
        }
      }
      if (verbResult != null) {
        verbResult = verbResult.replaceFirst('data:', '');
        batchResponse[id] = verbResult;
      }
    }
    if (batchRequests.isNotEmpty) {
      var result = _sendBatch(batchRequests);
      batchResponse = _prepareBatchResponse(batchResponse, result);
    }
    return jsonEncode(batchResponse);
  }

  BatchVerbBuilder buildBatchCommand() {
    return BatchVerbBuilder(currentAtSign);
  }

  dynamic runBatch(BatchVerbBuilder batchVerbBuilder) async {
    var batchRequests = batchVerbBuilder.batch();
    var batchResponse = await _runBatch(batchRequests);
    return batchResponse;
  }

  Future<VerbBuilder> prepareUpdateBuilder(String key, dynamic value,
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
    if (value != null) {
      if (sharedWith != null && sharedWith != currentAtSign) {
        try {
          builder.value =
              await encryptionService.encrypt(key, value, sharedWith);
        } on KeyNotFoundException catch (e) {
          var errorCode = AtClientExceptionUtil.getErrorCode(e);
          return Future.error(AtClientException(
              errorCode, AtClientExceptionUtil.getErrorDescription(errorCode)));
        }
      } else if (!builder.isPublic &&
          !builder.atKey.toString().startsWith('_')) {
        builder.value = await encryptionService.encryptForSelf(key, value);
        builder.isEncrypted = true;
      }
    }
    var isSyncRequired;
    if (updateKey.startsWith(AT_PKAM_PRIVATE_KEY) ||
        updateKey.startsWith(AT_PKAM_PUBLIC_KEY)) {
      builder.sharedBy = null;
    }
    if (SyncUtil.shouldSkipSync(updateKey)) {
      isSyncRequired = false;
    }
    //sign public data with private encryption key
    if (metadata != null && metadata.isPublic) {
      try {
        var encryptionPrivateKey =
            await _localSecondary.getEncryptionPrivateKey();
        if (encryptionPrivateKey != null) {
          logger.finer('signing public data for key:${key}');
          builder.dataSignature =
              encryptionService.signPublicData(encryptionPrivateKey, value);
        }
      } on Exception catch (e) {
        logger.severe('Exception trying to sign public data:${e.toString()}');
      }
    }
    return builder;
  }

  Map _prepareBatchResponse(Map batchResponse, result) {
    for (var entry in result) {
      var batchId = entry['id'];
      var serverResponse = entry['response'];
      batchResponse[batchId] = serverResponse;
    }
  }
}
