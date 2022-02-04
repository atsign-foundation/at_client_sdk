import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/manager/sync_manager_impl.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/service/file_transfer_service.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_client/src/transformer/request_transformer/get_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
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

  AtClientManager? _atClientManager;

  final _logger = AtSignLogger('AtClientImpl');
  static final Map _atClientInstanceMap = <String, AtClient>{};

  /// Returns a new instance of [AtClient]. App has to pass the current user atSign
  /// and the client preference.
  @Deprecated("Use AtClientManger to get instance of atClient")
  static Future<AtClient?> getClient(String? currentAtSign) async {
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return _atClientInstanceMap[currentAtSign];
    }
    AtSignLogger('AtClientImpl')
        .severe('Instance of atclientimpl for $currentAtSign is not created');
    return null;
  }

  @Deprecated("Use [create]")

  /// use [create]
  static Future<void> createClient(String currentAtSign, String? namespace,
      AtClientPreference preferences) async {
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

  @Deprecated("Use [create]")
  AtClientImpl(
      String _atSign, String? namespace, AtClientPreference preference) {
    currentAtSign = AtUtils.formatAtSign(_atSign);
    _preference = preference;
    _namespace = namespace;
  }

  static Future<AtClient> create(
      String currentAtSign, String? namespace, AtClientPreference preferences,
      {AtClientManager? atClientManager}) async {
    currentAtSign = AtUtils.formatAtSign(currentAtSign)!;
    if (_atClientInstanceMap.containsKey(currentAtSign)) {
      return _atClientInstanceMap[currentAtSign];
    }
    if (preferences.isLocalStoreRequired) {
      var storageManager = StorageManager(preferences);
      await storageManager.init(currentAtSign, preferences.keyStoreSecret);
    }
    atClientManager ??= AtClientManager.getInstance();
    var atClientImpl =
        AtClientImpl._(currentAtSign, namespace, preferences, atClientManager);
    await atClientImpl._init();
    _atClientInstanceMap[currentAtSign] = atClientImpl;
    return _atClientInstanceMap[currentAtSign];
  }

  AtClientImpl._(String _atSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager) {
    currentAtSign = AtUtils.formatAtSign(_atSign);
    _preference = preference;
    _preference?.namespace ??= namespace;
    _namespace = namespace;
    _atClientManager = atClientManager;
  }

  Future<void> _init() async {
    if (_preference!.isLocalStoreRequired) {
      _localSecondary = LocalSecondary(this);
    }
    _remoteSecondary = RemoteSecondary(currentAtSign!, _preference!,
        privateKey: _preference!.privateKey);
    _encryptionService = EncryptionService();
    _encryptionService!.remoteSecondary = _remoteSecondary;
    _encryptionService!.currentAtSign = currentAtSign;
    _encryptionService!.localSecondary = _localSecondary;
  }

  Secondary getSecondary() {
    if (_preference!.isLocalStoreRequired) {
      return _localSecondary!;
    }
    return _remoteSecondary!;
  }

  @override
  Future<void> startMonitor(String privateKey, Function? notificationCallback,
      {String? regex}) async {
    var monitorVerbBuilder = MonitorVerbBuilder();
    if (regex != null) {
      monitorVerbBuilder.regex = regex;
    }
    await _remoteSecondary!.monitor(
        monitorVerbBuilder.buildCommand(), notificationCallback, privateKey);
  }

  @override
  LocalSecondary? getLocalSecondary() {
    return _localSecondary;
  }

  @override
  RemoteSecondary? getRemoteSecondary() {
    return _remoteSecondary;
  }

  @override
  @Deprecated("Use SyncManager.sync")
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
    var privateKeyData =
        await getLocalSecondary()!.keyStore!.get(AT_PKAM_PRIVATE_KEY);
    var privateKey = privateKeyData?.data;
    return privateKey;
  }

  @override
  Future<bool> delete(AtKey atKey, {bool isDedicated = false}) {
    var isPublic = atKey.metadata != null ? atKey.metadata!.isPublic! : false;
    var isCached = atKey.metadata != null ? atKey.metadata!.isCached : false;
    var isNamespaceAware =
        atKey.metadata != null ? atKey.metadata!.namespaceAware : true;
    return _delete(atKey.key!,
        sharedWith: atKey.sharedWith,
        sharedBy: atKey.sharedBy,
        isPublic: isPublic,
        isCached: isCached,
        namespaceAware: isNamespaceAware);
  }

  Future<bool> _delete(String key,
      {String? sharedWith,
      String? sharedBy,
      bool isPublic = false,
      bool isCached = false,
      bool namespaceAware = true}) async {
    String keyWithNamespace;
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
    var deleteResult = await getSecondary().executeVerb(builder, sync: true);
    return deleteResult != null;
  }

  @override
  Future<AtValue> get(AtKey atKey, {bool isDedicated = false}) async {
    // validate the get request.
    await AtClientValidation.validateAtKey(atKey);
    // Get the verb builder for the atKey
    var verbBuilder = GetRequestTransformer().transform(atKey);
    // Execute the verb.
    var getResponse = await SecondaryManager.getSecondary(verbBuilder)
        .executeVerb(verbBuilder);
    // Return empty value if getResponse is null.
    if (getResponse == null ||
        getResponse.isEmpty ||
        getResponse == 'data:null') {
      return AtValue();
    }
    // Send AtKey and AtResponse to transform the response to AtValue.
    var getResponseTuple = Tuple<AtKey, String>()
      ..one = atKey
      ..two = (getResponse);
    // Transform the response and return
    return GetResponseTransformer().transform(getResponseTuple);
  }

  @override
  Future<Metadata?> getMeta(AtKey atKey, {bool isDedicated = false}) async {
    var atValue = await get(atKey);
    return atValue.metadata;
  }

  @override
  Future<List<String>> getKeys(
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool isDedicated = false}) async {
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
    return result as FutureOr<List<String>>;
  }

  @override
  Future<List<AtKey>> getAtKeys(
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool isDedicated = false}) async {
    var getKeysResult = await getKeys(
        regex: regex,
        sharedBy: sharedBy,
        sharedWith: sharedWith,
        isDedicated: isDedicated);
    var result = <AtKey>[];
    if (getKeysResult.isNotEmpty) {
      for (var key in getKeysResult) {
        try {
          result.add(AtKey.fromString(key));
        } on InvalidSyntaxException {
          _logger.severe('$key is not a well-formed key');
        } on Exception catch (e) {
          _logger.severe(
              'Exception occured: ${e.toString()}. Unable to form key $key');
        }
      }
    }
    return result;
  }

  Future<bool> _put(String key, dynamic value,
      {String? sharedWith, Metadata? metadata}) async {
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
      if ((sharedWith != null && sharedWith.isNotEmpty) &&
          sharedWith != currentAtSign) {
        try {
          builder.value =
              await _encryptionService!.encrypt(key, value, sharedWith);
          builder.isEncrypted = true;
        } on KeyNotFoundException catch (e) {
          var errorCode = AtClientExceptionUtil.getErrorCode(e);
          return Future.error(AtClientException(errorCode, e.message));
        }
      } else if (!builder.isPublic &&
          !builder.atKey.toString().startsWith('_')) {
        builder.value = await _encryptionService!.encryptForSelf(key, value);
        builder.isEncrypted = true;
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
    //sign public data with private encryption key
    if (metadata != null && metadata.isPublic!) {
      try {
        var encryptionPrivateKey =
            await _localSecondary!.getEncryptionPrivateKey();
        if (encryptionPrivateKey != null) {
          _logger.finer('signing public data for key:$key');
          builder.dataSignature =
              _encryptionService!.signPublicData(encryptionPrivateKey, value);
        }
      } on Exception catch (e) {
        _logger.severe('Exception trying to sign public data:${e.toString()}');
      }
    }

    String? putResult;
    try {
      if (builder.dataSignature != null) {
        builder.isJson = true;
      }
      putResult =
          await getSecondary().executeVerb(builder, sync: isSyncRequired);
    } on AtClientException catch (e) {
      _logger.severe(
          'error code: ${e.errorCode} error message: ${e.errorMessage}');
    } on Exception catch (e) {
      _logger.severe('error in put: ${e.toString()}');
    }
    return putResult != null;
  }

  @override
  Future<bool> put(AtKey atKey, dynamic value,
      {bool isDedicated = false}) async {
    if (atKey.metadata != null && atKey.metadata!.isBinary!) {
      if (value != null && value.length > _preference!.maxDataSize) {
        throw AtClientException('AT0005', 'BufferOverFlowException');
      }
      value = Base2e15.encode(value);
    }
    return _put(atKey.key!, value,
        sharedWith: atKey.sharedWith, metadata: atKey.metadata);
  }

  @override
  Future<bool> notify(AtKey atKey, String value, OperationEnum operation,
      {MessageTypeEnum? messageType,
      PriorityEnum? priority,
      StrategyEnum? strategy,
      int? latestN,
      String? notifier = SYSTEM,
      bool isDedicated = false}) async {
    final notificationParams =
        NotificationParams.forUpdate(atKey, value: value);
    final notifyResult =
        await _atClientManager!.notificationService.notify(notificationParams);
    return notifyResult.notificationStatusEnum ==
        NotificationStatusEnum.delivered;
  }

  @override
  Future<String> notifyAll(AtKey atKey, String value, OperationEnum operation,
      {bool isDedicated = false}) async {
    var returnMap = {};
    var sharedWithList = jsonDecode(atKey.sharedWith!);
    for (var sharedWith in sharedWithList) {
      atKey.sharedWith = sharedWith;
      final notificationParams =
          NotificationParams.forUpdate(atKey, value: value);
      final notifyResult = await _atClientManager!.notificationService
          .notify(notificationParams);
      returnMap.putIfAbsent(
          sharedWith,
          () => (notifyResult.notificationStatusEnum ==
              NotificationStatusEnum.delivered));
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
  Future<String> notifyList(
      {String? fromDate,
      String? toDate,
      String? regex,
      bool isDedicated = false}) async {
    try {
      var builder = NotifyListVerbBuilder()
        ..fromDate = fromDate
        ..toDate = toDate
        ..regex = regex;
      var notifyList = await getRemoteSecondary()!.executeVerb(builder);
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

    var updateMetaResult =
        await getSecondary().executeVerb(builder, sync: isSyncRequired);
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
    var isMetadataNotNull = AtClientUtil.isAnyNotNull(
        a1: data!.ttl,
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

  String _formatResult(String? commandResult) {
    var result = commandResult;
    if (result != null) {
      result = result.replaceFirst('data:', '');
    }
    return result ??= '';
  }

  @override
  Future<AtStreamResponse> stream(String sharedWith, String filePath,
      {String? namespace}) async {
    var streamResponse = AtStreamResponse();
    var streamId = Uuid().v4();
    var file = File(filePath);
    var data = file.readAsBytesSync();
    var fileName = basename(filePath);
    fileName = base64.encode(utf8.encode(fileName));
    var encryptedData =
        await _encryptionService!.encryptStream(data, sharedWith);
    var command =
        'stream:init$sharedWith namespace:$namespace $streamId $fileName ${encryptedData.length}\n';
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
        streamResponse.status = AtStreamStatus.complete;
      }
    } else if (result != null && result.startsWith('error:')) {
      result = result.replaceAll('error:', '');
      streamResponse.errorCode = result.split('-')[0];
      streamResponse.errorMessage = result.split('-')[1];
      streamResponse.status = AtStreamStatus.error;
    } else {
      streamResponse.status = AtStreamStatus.noAck;
    }
    return streamResponse;
  }

  @override
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
    handler.encryptionService = _encryptionService;
    var notification = AtStreamNotification()
      ..streamId = streamId
      ..fileName = fileName
      ..currentAtSign = currentAtSign!
      ..senderAtSign = senderAtSign
      ..fileLength = fileLength;
    _logger.info('Sending ack for stream notification:$notification');
    await handler.streamAck(
        notification, streamCompletionCallBack, streamReceiveCallBack);
  }

  @override
  Future<Map<String, FileTransferObject>> uploadFile(
      List<File> files, List<String> sharedWithAtSigns) async {
    var encryptionKey = _encryptionService!.generateFileEncryptionKey();
    var key = TextConstants.fileTransferKey + Uuid().v4();
    var fileStatus = await _uploadFiles(key, files, encryptionKey);
    var fileUrl = TextConstants.fileBinURL + 'archive/' + key + '/zip';
    return shareFiles(
        sharedWithAtSigns, key, fileUrl, encryptionKey, fileStatus);
  }

  @override
  Future<Map<String, FileTransferObject>> shareFiles(
      List<String> sharedWithAtSigns,
      String key,
      String fileUrl,
      String encryptionKey,
      List<FileStatus> fileStatus,
      {DateTime? date}) async {
    var result = <String, FileTransferObject>{};
    for (var sharedWithAtSign in sharedWithAtSigns) {
      var fileTransferObject = FileTransferObject(
          key, encryptionKey, fileUrl, sharedWithAtSign, fileStatus,
          date: date);
      try {
        var atKey = AtKey()
          ..key = key
          ..sharedWith = sharedWithAtSign
          ..metadata = Metadata()
          ..metadata!.ttr = -1
          // file transfer key will be deleted after 30 days
          ..metadata!.ttl = 2592000000
          ..sharedBy = currentAtSign;

        var notificationResult =
            await _atClientManager!.notificationService.notify(
          NotificationParams.forUpdate(
            atKey,
            value: jsonEncode(fileTransferObject.toJson()),
          ),
        );

        if (notificationResult.notificationStatusEnum ==
            NotificationStatusEnum.delivered) {
          fileTransferObject.sharedStatus = true;
        } else {
          fileTransferObject.sharedStatus = false;
        }
      } on Exception catch (e) {
        fileTransferObject.sharedStatus = false;
        fileTransferObject.error = e.toString();
      }
      result[sharedWithAtSign] = fileTransferObject;
    }
    return result;
  }

  Future<List<FileStatus>> _uploadFiles(
      String transferId, List<File> files, String encryptionKey) async {
    var fileStatuses = <FileStatus>[];
    for (var file in files) {
      var fileStatus = FileStatus(
        fileName: file.path.split('/').last,
        isUploaded: false,
        size: await file.length(),
      );
      try {
        final encryptedFile = await _encryptionService!.encryptFileInChunks(
            file, encryptionKey, _preference!.fileEncryptionChunkSize);
        var response =
            await FileTransferService().uploadToFileBinWithStreamedRequest(
          encryptedFile,
          transferId,
          fileStatus.fileName!,
        );
        encryptedFile.deleteSync();
        if (response != null && response.statusCode == 201) {
          final responseStr = await response.stream.bytesToString();
          var responseMap = jsonDecode(responseStr);
          fileStatus.fileName = responseMap['file']['filename'];
          fileStatus.isUploaded = true;
        }

        // storing sent files in a a directory.
        if (preference?.downloadPath != null) {
          var sentFilesDirectory =
              await Directory(preference!.downloadPath! + '/sent-files')
                  .create();
          await File(file.path)
              .copy(sentFilesDirectory.path + '/${fileStatus.fileName}');
        }
      } on Exception catch (e) {
        fileStatus.error = e.toString();
      }
      fileStatuses.add(fileStatus);
    }
    return fileStatuses;
  }

  @override
  Future<List<FileStatus>> reuploadFiles(
      List<File> files, FileTransferObject fileTransferObject) async {
    var response = await _uploadFiles(fileTransferObject.transferId, files,
        fileTransferObject.fileEncryptionKey);
    return response;
  }

  @override
  Future<List<File>> downloadFile(String transferId, String sharedByAtSign,
      {String? downloadPath}) async {
    downloadPath ??= preference!.downloadPath;
    if (downloadPath == null) {
      throw Exception('downloadPath not found');
    }
    var atKey = AtKey()
      ..key = transferId
      ..sharedBy = sharedByAtSign;
    var result = await get(atKey);
    FileTransferObject fileTransferObject;
    try {
      if (FileTransferObject.fromJson(jsonDecode(result.value)) == null) {
        _logger.severe("FileTransferObject is null");
        throw AtClientException("AT0014", "FileTransferObject is null");
      }
      fileTransferObject =
          FileTransferObject.fromJson(jsonDecode(result.value))!;
    } on Exception catch (e) {
      throw Exception('json decode exception in download file ${e.toString()}');
    }
    var downloadedFiles = <File>[];
    var fileDownloadReponse = await FileTransferService()
        .downloadFromFileBin(fileTransferObject, downloadPath);
    if (fileDownloadReponse.isError) {
      throw Exception('download fail');
    }
    var encryptedFileList = Directory(fileDownloadReponse.filePath!).listSync();
    try {
      for (var encryptedFile in encryptedFileList) {
        var decryptedFile = await _encryptionService!.decryptFileInChunks(
            File(encryptedFile.path),
            fileTransferObject.fileEncryptionKey,
            _preference!.fileEncryptionChunkSize);
        decryptedFile
            .copySync(downloadPath + '/' + encryptedFile.path.split('/').last);
        downloadedFiles
            .add(File(downloadPath + '/' + encryptedFile.path.split('/').last));
        decryptedFile.deleteSync();
      }
      // deleting temp directory
      Directory(fileDownloadReponse.filePath!).deleteSync(recursive: true);
      return downloadedFiles;
    } catch (e) {
      print('error in downloadFile: $e');
      return [];
    }
  }

  @Deprecated("Use EncryptionService")
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
      throw AtClientException(
          atClientErrorCodes['AtClientException'], 'No network availability');
    }
    // validate sharedWith atSign
    AtUtils.fixAtSign(notificationParams.atKey.sharedWith!);
    // Check if sharedWith AtSign exists
    AtClientValidation.isAtSignExists(notificationParams.atKey.sharedWith!,
        _preference!.rootDomain, _preference!.rootPort);
    // validate sharedBy atSign
    notificationParams.atKey.sharedBy ??= getCurrentAtSign();
    AtUtils.fixAtSign(notificationParams.atKey.sharedBy!);
    // validate atKey
    // For messageType is text, text may contains spaces but key should not have spaces
    // Hence do not validate the key.
    if (notificationParams.messageType != MessageTypeEnum.text) {
      AtClientValidation.validateKey(notificationParams.atKey.key);
    }
    // validate metadata
    AtClientValidation.validateMetadata(notificationParams.atKey.metadata);
    // If namespaceAware is set to true, append nameSpace to key.
    if (notificationParams.atKey.metadata != null &&
        notificationParams.atKey.metadata!.namespaceAware) {
      notificationParams.atKey.key =
          _getKeyWithNamespace(notificationParams.atKey.key!);
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
    if (notificationParams.value != null &&
        notificationParams.value!.isNotEmpty) {
      // If atKey is being notified to another atSign, encrypt data with other
      // atSign encryption public key.
      if (notificationParams.atKey.sharedWith != null &&
          notificationParams.atKey.sharedWith != currentAtSign) {
        try {
          builder.value = await _encryptionService!.encrypt(
              notificationParams.atKey.key,
              notificationParams.value!,
              notificationParams.atKey.sharedWith!);
        } on KeyNotFoundException catch (e) {
          var errorCode = AtClientExceptionUtil.getErrorCode(e);
          return Future.error(AtClientException(errorCode, e.message));
        }
      }
      // If sharedWith is currentAtSign, encrypt data with currentAtSign encryption public key.
      if (notificationParams.atKey.sharedWith == null ||
          notificationParams.atKey.sharedWith == currentAtSign) {
        builder.value = await _encryptionService!.encryptForSelf(
            notificationParams.atKey.key, notificationParams.value!);
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
