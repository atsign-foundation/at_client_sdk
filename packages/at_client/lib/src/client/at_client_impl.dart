import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/compaction/at_commit_log_compaction.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/manager/sync_manager_impl.dart';
import 'package:at_client/src/preference/at_client_config.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/service/file_transfer_service.dart';
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_client/src/transformer/request_transformer/get_request_transformer.dart';
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/put_response_transformer.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:version/version.dart';

/// Implementation of [AtClient] interface and [AtSignChangeListener] interface
///
/// Implements to [AtSignChangeListener] to get notified on switch atSign event. On switch atSign event,
/// pause's the compaction job on currentAtSign and start/resume the compaction job on the new atSign
class AtClientImpl implements AtClient, AtSignChangeListener {
  AtClientPreference? _preference;

  AtClientPreference? get preference => _preference;
  late final String _atSign;
  String? _namespace;
  SecondaryKeyStore? _localSecondaryKeyStore;
  LocalSecondary? _localSecondary;
  RemoteSecondary? _remoteSecondary;
  AtClientCommitLogCompaction? _atClientCommitLogCompaction;
  AtClientConfig? _atClientConfig;
  static final upperCaseRegex = RegExp(r'[A-Z]');

  PutRequestTransformer putRequestTransformer = PutRequestTransformer();

  AtClientCommitLogCompaction? get atClientCommitLogCompaction =>
      _atClientCommitLogCompaction;

  @override
  // ignore: override_on_non_overriding_member
  AtChops? _atChops;

  EncryptionService? _encryptionService;

  @experimental
  AtTelemetryService? _telemetry;

  @override
  @experimental
  set telemetry(AtTelemetryService? telemetryService) {
    _telemetry = telemetryService;
    _cascadeSetTelemetryService();
  }

  @override
  @experimental
  AtTelemetryService? get telemetry => _telemetry;

  @override
  set atChops(AtChops? atChops) {
    _atChops = atChops;
  }

  @override
  AtChops? get atChops => _atChops;

  late SyncService _syncService;

  @override
  set syncService(SyncService syncService) {
    _syncService = syncService;
  }

  @override
  SyncService get syncService => _syncService;

  late NotificationService _notificationService;

  @override
  set notificationService(NotificationService notificationService) {
    _notificationService = notificationService;
  }

  EnrollmentService? _enrollmentService;

  @override
  set enrollmentService(EnrollmentService? enrollmentService) {
    _enrollmentService = enrollmentService;
  }

  @override
  EnrollmentService? get enrollmentService => _enrollmentService;

  @override
  NotificationService get notificationService => _notificationService;

  @override
  EncryptionService? get encryptionService => _encryptionService;

  late final AtClientManager _atClientManager;

  late final AtSignLogger _logger;

  @override
  String? enrollmentId;

  @visibleForTesting
  static final Map atClientInstanceMap = <String, AtClient>{};

  static Future<AtClient> create(
      String currentAtSign, String? namespace, AtClientPreference preferences,
      {AtClientManager? atClientManager,
      RemoteSecondary? remoteSecondary,
      EncryptionService? encryptionService,
      SecondaryKeyStore? localSecondaryKeyStore,
      AtChops? atChops,
      AtClientCommitLogCompaction? atClientCommitLogCompaction,
      AtClientConfig? atClientConfig,
      String? enrollmentId}) async {
    atClientManager ??= AtClientManager.getInstance();
    currentAtSign = AtUtils.fixAtSign(currentAtSign);

    // Fetch cached AtClientImpl for re-use, or create a new one and init it
    AtClientImpl? atClientImpl;
    if (atClientInstanceMap.containsKey(currentAtSign)) {
      atClientImpl = atClientInstanceMap[currentAtSign];
    } else {
      atClientImpl = AtClientImpl._(
          currentAtSign, namespace, preferences, atClientManager,
          remoteSecondary: remoteSecondary,
          encryptionService: encryptionService,
          localSecondaryKeyStore: localSecondaryKeyStore,
          atChops: atChops,
          atClientCommitLogCompaction: atClientCommitLogCompaction,
          atClientConfig: atClientConfig,
          enrollmentId: enrollmentId);

      await atClientImpl._init();
    }

    await atClientImpl!.startCompactionJob();
    atClientManager.listenToAtSignChange(atClientImpl);

    atClientInstanceMap[currentAtSign] = atClientImpl;
    return atClientInstanceMap[currentAtSign];
  }

  AtClientImpl._(String theAtSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager,
      {RemoteSecondary? remoteSecondary,
      EncryptionService? encryptionService,
      SecondaryKeyStore? localSecondaryKeyStore,
      AtChops? atChops,
      AtClientCommitLogCompaction? atClientCommitLogCompaction,
      AtClientConfig? atClientConfig,
      this.enrollmentId}) {
    _atSign = AtUtils.fixAtSign(theAtSign);
    _logger = AtSignLogger('AtClientImpl ($_atSign)');
    _preference = preference;
    _preference?.namespace ??= namespace;
    _namespace = namespace;
    _atClientManager = atClientManager;
    _localSecondaryKeyStore = localSecondaryKeyStore;
    if (_localSecondaryKeyStore != null && !_preference!.isLocalStoreRequired) {
      throw IllegalArgumentException(
          'A SecondaryKeyStore was injected, but preference.isLocalStoreRequired is false');
    }
    _remoteSecondary = remoteSecondary;
    _encryptionService = encryptionService;
    _atChops = atChops;
    _atClientCommitLogCompaction = atClientCommitLogCompaction;
  }

  Future<void> _init() async {
    if (_preference!.isLocalStoreRequired) {
      if (_localSecondaryKeyStore == null) {
        var storageManager = StorageManager(preference);
        await storageManager.init(_atSign, preference!.keyStoreSecret);
      }

      _localSecondary = LocalSecondary(this, keyStore: _localSecondaryKeyStore);
      _atChops ??= await _createAtChops(_atSign);
    }

    // Now using ??= because we may be injecting a RemoteSecondary
    _remoteSecondary ??= RemoteSecondary(_atSign, _preference!,
        atChops: atChops,
        privateKey: _preference!.privateKey,
        enrollmentId: enrollmentId);

    // Now using ??= because we may be injecting an EncryptionService
    _encryptionService ??= EncryptionService(_atSign);
    _encryptionService!.remoteSecondary = _remoteSecondary;
    _encryptionService!.localSecondary = _localSecondary;

    putRequestTransformer.atClient = this;

    _cascadeSetTelemetryService();
  }

  @override
  Future<void> startCompactionJob(
      {Duration? commitLogCompactionDuration}) async {
    commitLogCompactionDuration ??= Duration(
        minutes:
            AtClientConfig.getInstance().commitLogCompactionTimeIntervalInMins);
    AtCompactionJob atCompactionJob = AtCompactionJob(
        (await AtCommitLogManagerImpl.getInstance().getCommitLog(_atSign))!,
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(_atSign)!);

    _atClientCommitLogCompaction ??=
        AtClientCommitLogCompaction.create(_atSign, atCompactionJob);

    _atClientConfig ??= AtClientConfig.getInstance();

    if (!_atClientCommitLogCompaction!.isCompactionJobRunning()) {
      _atClientCommitLogCompaction!
          .scheduleCompaction(commitLogCompactionDuration.inMinutes);
    }
  }

  @override
  Future<void> stopCompactionJob() async {
    _logger.info('Stopping the commit log compaction job');
    await _atClientCommitLogCompaction?.stopCompactionJob();
  }

  /// Does nothing unless a telemetry service has been injected
  void _cascadeSetTelemetryService() {
    if (telemetry != null) {
      _encryptionService?.telemetry = telemetry;
      _localSecondary?.telemetry = telemetry;
      _remoteSecondary?.telemetry = telemetry;
    }
  }

  Secondary getSecondary() {
    if (_preference!.isLocalStoreRequired) {
      return _localSecondary!;
    }
    return _remoteSecondary!;
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
  void setPreferences(AtClientPreference preference) async {
    _preference = preference;
  }

  Future<bool> persistPrivateKey(String privateKey) async {
    var atData = AtData();
    atData.data = privateKey.toString();
    await _localSecondary!.keyStore!.put(AtConstants.atPkamPrivateKey, atData);
    return true;
  }

  Future<bool> persistPublicKey(String publicKey) async {
    var atData = AtData();
    atData.data = publicKey.toString();
    await getLocalSecondary()!
        .keyStore!
        .put(AtConstants.atPkamPublicKey, atData);
    return true;
  }

  Future<String?> getPrivateKey(String atSign) async {
    var privateKeyData =
        await getLocalSecondary()!.keyStore!.get(AtConstants.atPkamPrivateKey);
    var privateKey = privateKeyData?.data;
    return privateKey;
  }

  @override
  Future<bool> delete(AtKey atKey,
      {bool isDedicated = false, DeleteRequestOptions? deleteRequestOptions}) {
    _telemetry?.controller.sink
        .add(AtTelemetryEvent('AtClient.delete called', {"key": atKey}));
    // ignore: no_leading_underscores_for_local_identifiers
    var _deleteResult =
        _delete(atKey, deleteRequestOptions: deleteRequestOptions);
    _telemetry?.controller.sink.add(AtTelemetryEvent('AtClient.delete complete',
        {"key": atKey, "_deleteResult": _deleteResult}));
    return _deleteResult;
  }

  Future<bool> _delete(AtKey atKey,
      {DeleteRequestOptions? deleteRequestOptions}) async {
    atKey.sharedBy ??= _atSign;
    // When namespace is not set in AtKey.namespace, default it to namespace from
    // AtClientPreferences
    if (atKey.metadata.namespaceAware) {
      atKey.namespace ??= preference?.namespace;
    }
    var builder = DeleteVerbBuilder()..atKey = atKey;
    var secondary = getSecondary();
    if (deleteRequestOptions != null &&
        deleteRequestOptions.useRemoteAtServer) {
      secondary = getRemoteSecondary()!;
    }
    var deleteResult = await secondary.executeVerb(builder, sync: true);

    return deleteResult != null;
  }

  @override
  Future<AtValue> get(AtKey atKey,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions}) async {
    Secondary? secondary;
    try {
      // validate the get request.
      await AtClientValidation().validateAtKey(atKey);
      // Get the verb builder for the atKey
      var verbBuilder = GetRequestTransformer(this)
          .transform(atKey, requestOptions: getRequestOptions);
      // Execute the verb.
      if (getRequestOptions?.useRemoteAtServer == true) {
        secondary = getRemoteSecondary()!;
      } else {
        secondary = SecondaryManager.getSecondary(this, verbBuilder);
      }
      var getResponse = await secondary.executeVerb(verbBuilder);
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
      var atValue =
          await GetResponseTransformer(this).transform(getResponseTuple);
      return atValue;
    } on AtException catch (e) {
      var exceptionScenario = (secondary is LocalSecondary)
          ? ExceptionScenario.localVerbExecutionFailed
          : ExceptionScenario.remoteVerbExecutionFailed;
      e.stack(
          AtChainedException(Intent.fetchData, exceptionScenario, e.message));
      throw AtExceptionManager.createException(e);
    }
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
      bool showHiddenKeys = false}) async {
    var builder = ScanVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = sharedBy
      ..regex = regex
      ..showHiddenKeys = showHiddenKeys
      ..auth = true;
    var scanResult = await getSecondary().executeVerb(builder);
    scanResult = _formatResult(scanResult);
    var result = [];
    if (scanResult.isNotEmpty) {
      result = List<String>.from(jsonDecode(scanResult));
    }
    return result as FutureOr<List<String>>;
  }

  @override
  Future<List<AtKey>> getAtKeys(
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool showHiddenKeys = false}) async {
    var getKeysResult = await getKeys(
        regex: regex,
        sharedBy: sharedBy,
        sharedWith: sharedWith,
        showHiddenKeys: showHiddenKeys);
    var result = <AtKey>[];
    if (getKeysResult.isNotEmpty) {
      for (var key in getKeysResult) {
        try {
          result.add(AtKey.fromString(key));
        } on InvalidSyntaxException {
          _logger.severe('$key is not a well-formed key');
        } on Exception catch (e) {
          _logger.severe(
              'Exception occurred: ${e.toString()}. Unable to form key $key');
        }
      }
    }
    return result;
  }

  @override
  Future<bool> put(AtKey atKey, dynamic value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    _telemetry?.controller.sink
        .add(AtTelemetryEvent('AtClient.put called', {"key": atKey}));
    // If the value is neither String nor List<int> throw exception
    if (value is! String && value is! List<int>) {
      throw AtValueException(
          'Invalid value type found ${value.runtimeType}. Expected String or List<int>');
    }
    AtResponse atResponse = AtResponse();
    if (value is String) {
      atResponse =
          await putText(atKey, value, putRequestOptions: putRequestOptions);
    }
    if (value is List<int>) {
      atResponse =
          await putBinary(atKey, value, putRequestOptions: putRequestOptions);
    }
    _telemetry?.controller.sink
        .add(AtTelemetryEvent('AtClient.put complete', {"atKey": atKey}));
    return atResponse.response.isNotEmpty;
  }

  /// put's the text data into the keystore
  @override
  Future<AtResponse> putText(AtKey atKey, String value,
      {PutRequestOptions? putRequestOptions}) async {
    try {
      // Setting metadata.isBinary to false for putText
      atKey.metadata.isBinary = false;
      return await _putInternal(atKey, value, putRequestOptions);
    } on AtException catch (e) {
      throw AtExceptionManager.createException(e);
    }
  }

  /// put's the binary data(e.g. images, files etc) into the keystore
  @override
  Future<AtResponse> putBinary(AtKey atKey, List<int> value,
      {PutRequestOptions? putRequestOptions}) async {
    try {
      // Setting metadata.isBinary to true for putBinary
      atKey.metadata.isBinary = true;
      // Base2e15.encode method converts the List<int> type to String.
      return await _putInternal(
          atKey, Base2e15.encode(value), putRequestOptions);
    } on AtException catch (e) {
      throw AtExceptionManager.createException(e);
    }
  }

  @visibleForTesting
  ensureLowerCase(AtKey atKey) {
    if (upperCaseRegex.hasMatch(atKey.key) ||
        (atKey.namespace != null &&
            upperCaseRegex.hasMatch(atKey.namespace!))) {
      _logger.finer('AtKey: ${atKey.toString()} previously contained upper case'
          ' characters, AtKey has been converted to lower case');
      //AtKey.toString() in the above log will convert the entire key to lower case
    }
  }

  Future<AtResponse> _putInternal(
      AtKey atKey, dynamic value, PutRequestOptions? putRequestOptions) async {
    // Performs the put request validations.
    AtClientValidation.validatePutRequest(atKey, value, preference!);
    // Set sharedBy to currentAtSign if not set.
    if (atKey.sharedBy.isNull) {
      atKey.sharedBy = _atSign;
    }
    if (atKey.metadata.namespaceAware) {
      atKey.namespace ??= preference?.namespace;
    }

    if (preference!.atProtocolEmitted >= Version(2, 0, 0)) {
      atKey.metadata.ivNonce ??= EncryptionUtil.generateIV();
    }
    ensureLowerCase(atKey);

    // validate the atKey
    // * Setting the validateOwnership to true to perform KeyOwnerShip validation and KeyShare validation
    // * Setting enforceNamespace to true unless specifically set to false in the AtClientPreference
    bool enforceNamespace = true;
    // ignore: deprecated_member_use_from_same_package
    if (preference != null && preference!.enforceNamespace == false) {
      enforceNamespace = false;
    }
    var validationResult = AtKeyValidators.get().validate(
        atKey.toString(),
        ValidationContext()
          ..atSign = _atSign
          ..validateOwnership = true
          ..enforceNamespace = enforceNamespace);
    // If the validationResult.isValid is false, validation of AtKey failed.
    // throw AtClientException with failure reason.
    if (!validationResult.isValid) {
      throw AtKeyException(validationResult.failureReason);
    }
    var tuple = Tuple<AtKey, dynamic>()
      ..one = atKey
      ..two = value;

    //Get encryptionPrivateKey for public key to signData
    String? encryptionPrivateKey;
    if (atKey.metadata.isPublic == true) {
      encryptionPrivateKey = await _localSecondary?.getEncryptionPrivateKey();
    }
    // Transform put request
    // Optionally passing encryption private key to sign the public data.
    UpdateVerbBuilder verbBuilder = await putRequestTransformer.transform(tuple,
        encryptionPrivateKey: encryptionPrivateKey,
        requestOptions: putRequestOptions);
    // Validate the size of the value after encryption/encoding
    // Since AtClientPreference is mandatory argument in create method, _preference
    // will not be null.
    if (verbBuilder.value.length > _preference!.maxDataSize) {
      throw BufferOverFlowException(
          'The length of value exceeds the maximum allowed length. Maximum buffer size is ${_preference!.maxDataSize} bytes. Found ${value.toString().length} bytes');
    }

    Secondary secondary = SecondaryManager.getSecondary(this, verbBuilder);
    if (putRequestOptions != null && putRequestOptions.useRemoteAtServer) {
      secondary = getRemoteSecondary()!;
    }
    // Execute the verb builder
    var putResponse = await secondary.executeVerb(verbBuilder,
        sync: SyncUtil.shouldSync(atKey.key));
    // If putResponse is null or empty, return AtResponse with isError set to true
    if (putResponse == null || putResponse.isEmpty) {
      return AtResponse()..isError = true;
    }
    return await PutResponseTransformer().transform(putResponse);
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
    var metadata = atKey.metadata;
    if (metadata.namespaceAware) {
      updateKey = _getKeyWithNamespace(atKey.key);
    }
    var builder = UpdateVerbBuilder();
    builder
      ..atKey = atKey
      ..operation = AtConstants.updateMeta;

    var updateMetaResult = await getSecondary()
        .executeVerb(builder, sync: SyncUtil.shouldSync(updateKey));
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
      return AtConstants.value;
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
      return AtConstants.updateAll;
    }
    //If value is null and metadata is not null,
    if (value == null && isMetadataNotNull) {
      return AtConstants.updateMeta;
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

  Future<AtChops> _createAtChops(String atSign) async {
    AtEncryptionKeyPair? atEncryptionKeyPair;
    AtPkamKeyPair? atPkamKeyPair;
    try {
      var encryptionPublicKey =
          await _localSecondary!.getEncryptionPublicKey(atSign);
      var encryptionPrivateKey =
          await _localSecondary!.getEncryptionPrivateKey();
      if (encryptionPublicKey != null && encryptionPrivateKey != null) {
        atEncryptionKeyPair = AtEncryptionKeyPair.create(
            encryptionPublicKey, encryptionPrivateKey);
      }
    } on KeyNotFoundException catch (e) {
      _logger.warning(
          '_createAtChops  - Exception while getting encryption key pair from local secondary: ${e.toString()}');
    }
    try {
      var pkamPublicKey = await _localSecondary!.getPublicKey();
      var pkamPrivateKey = await _localSecondary!.getPrivateKey();

      if (pkamPublicKey != null && pkamPrivateKey != null) {
        atPkamKeyPair = AtPkamKeyPair.create(pkamPublicKey, pkamPrivateKey);
      }
    } on KeyNotFoundException catch (e) {
      _logger.warning(
          '_createAtChops  - Exception while getting pkam key pair from local secondary: ${e.toString()}');
    }
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    return AtChopsImpl(atChopsKeys);
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
    var remoteSecondary =
        RemoteSecondary(_atSign, _preference!, atChops: atChops);
    var result = await remoteSecondary.executeCommand(command, auth: true);
    _logger.finer('ack message:$result');
    if (result != null && result.startsWith('stream:ack')) {
      result = result.replaceAll('stream:ack ', '');
      result = result.trim();
      _logger.finer('ack received for streamId:$streamId');
      remoteSecondary.atLookUp.connection!.getSocket().add(encryptedData);
      var streamResult = await remoteSecondary.atLookUp.messageListener
          .read(maxWaitMilliSeconds: _preference!.outboundConnectionTimeout);
      if (streamResult.startsWith('stream:done')) {
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
      ..currentAtSign = _atSign
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
    // ignore: prefer_interpolation_to_compose_strings
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
          ..metadata.ttr = -1
          // file transfer key will be deleted after 30 days
          ..metadata.ttl = 2592000000
          ..sharedBy = _atSign;

        var notificationResult = await notificationService.notify(
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
        fileName: file.path.split(Platform.pathSeparator).last,
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
          var sentFilesDirectory = await Directory(
                  '${preference!.downloadPath!}${Platform.pathSeparator}sent-files')
              .create();
          await File(file.path).copy(sentFilesDirectory.path +
              Platform.pathSeparator +
              (fileStatus.fileName ?? ''));
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
        throw AtClientException(
            error_codes['AtClientException'], 'FileTransferObject is null');
      }
      fileTransferObject =
          FileTransferObject.fromJson(jsonDecode(result.value))!;
    } on Exception catch (e) {
      throw Exception('json decode exception in download file ${e.toString()}');
    }
    var downloadedFiles = <File>[];
    var fileDownloadResponse = await FileTransferService()
        .downloadFromFileBin(fileTransferObject, downloadPath);
    if (fileDownloadResponse.isError) {
      throw Exception('download fail');
    }
    var encryptedFileList =
        Directory(fileDownloadResponse.filePath!).listSync();
    try {
      for (var encryptedFile in encryptedFileList) {
        var decryptedFile = await _encryptionService!.decryptFileInChunks(
            File(encryptedFile.path),
            fileTransferObject.fileEncryptionKey,
            _preference!.fileEncryptionChunkSize,
            ivBase64: fileTransferObject.ivBase64);
        decryptedFile.copySync(downloadPath +
            Platform.pathSeparator +
            encryptedFile.path.split(Platform.pathSeparator).last);
        downloadedFiles.add(File(downloadPath +
            Platform.pathSeparator +
            encryptedFile.path.split(Platform.pathSeparator).last));
        decryptedFile.deleteSync();
      }
      // deleting temp directory
      Directory(fileDownloadResponse.filePath!).deleteSync(recursive: true);
      return downloadedFiles;
    } catch (e) {
      print('error in downloadFile: $e');
      return [];
    }
  }

  @override
  Future<AtResponse> setSPP(String spp) async {
    // SPP should be 6 characters PIN. Throw exception if its less
    // or more than 6 characters
    if (spp.length != 6) {
      throw InvalidPinException.message("$spp should be 6 characters");
    }
    // Validate the SPP. The SPP should contain only alpha-numeric characters.
    // Any special characters or any characters other than aplha-numeric characters
    // are not allowed. Throw an exception
    bool hasMatch = RegExp(r'[\W-]+').hasMatch(spp);
    if (hasMatch) {
      throw InvalidPinException.message("$spp is not a valid SPP");
    }
    String? otpVerbResponse;
    try {
      otpVerbResponse =
          await _remoteSecondary?.executeCommand('otp:put:$spp\n', auth: true);
    } on AtLookUpException catch (e) {
      throw AtClientException(e.errorCode, e.errorMessage);
    } on AtException catch (e) {
      throw AtClientException.message(e.message);
    }
    otpVerbResponse = otpVerbResponse?.replaceAll('data:', '');
    return AtResponse()..response = otpVerbResponse!;
  }

  @override
  Future<AtResponse> getOTP() async {
    String? otpVerbResponse;
    try {
      otpVerbResponse =
          await _remoteSecondary?.executeCommand('otp:get\n', auth: true);
    } on AtLookUpException catch (e) {
      throw AtClientException(e.errorCode, e.errorMessage);
    } on AtException catch (e) {
      throw AtClientException.message(e.message);
    }
    otpVerbResponse = otpVerbResponse?.replaceAll('data:', '');
    return AtResponse()..response = otpVerbResponse!;
  }

  @override
  String? getCurrentAtSign() => _atSign;

  @override
  AtClientPreference? getPreferences() {
    return _preference;
  }

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    // Checks if the instance of AtClientImpl belongs to previous atSign. If Yes,
    // the compaction job is stopped and removed from changeListener list.
    if (switchAtSignEvent.previousAtClient?.getCurrentAtSign() ==
        getCurrentAtSign()) {
      _atClientCommitLogCompaction!.stopCompactionJob();
      _atClientManager.removeChangeListeners(this);
    }
  }

  // TODO v4 - remove the follow methods in version 4 of at_client package

  @override
  @Deprecated("Use AtClient.syncService")
  SyncManager? getSyncManager() {
    return SyncManagerImpl.getInstance().getSyncManager(_atSign);
  }

  @override

  ///[Deprecated] Use [AtClient.notificationService]
  @Deprecated('Use AtClient.notificationService')
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
  @Deprecated("Use NotificationService")
  Future<bool> notify(AtKey atKey, String value, OperationEnum operation,
      {MessageTypeEnum? messageType,
      PriorityEnum? priority,
      StrategyEnum? strategy,
      int? latestN,
      String? notifier = AtConstants.system,
      bool isDedicated = false}) async {
    AtKeyValidators.get().validate(
        atKey.toString(),
        ValidationContext()
          ..atSign = _atSign
          ..validateOwnership = true);
    final notificationParams =
        NotificationParams.forUpdate(atKey, value: value);
    final notifyResult = await notificationService.notify(notificationParams);
    return notifyResult.notificationStatusEnum ==
        NotificationStatusEnum.delivered;
  }

  @override
  @Deprecated('Use NotificationService')
  Future<String> notifyAll(AtKey atKey, String value, OperationEnum operation,
      {bool isDedicated = false}) async {
    var returnMap = {};
    var sharedWithList = jsonDecode(atKey.sharedWith!);
    for (var sharedWith in sharedWithList) {
      atKey.sharedWith = sharedWith;
      final notificationParams =
          NotificationParams.forUpdate(atKey, value: value);
      final notifyResult = await notificationService.notify(notificationParams);
      returnMap.putIfAbsent(
          sharedWith,
          () => (notifyResult.notificationStatusEnum ==
              NotificationStatusEnum.delivered));
    }
    return jsonEncode(returnMap);
  }

  @override

  ///[Deprecated] Use [NotificationService.notify]
  @Deprecated("Use [NotificationService.notify]")
  Future<String?> notifyChange(NotificationParams notificationParams) async {
    NotificationResult result =
        await notificationService.notify(notificationParams);
    if (result.atClientException != null) {
      throw result.atClientException!;
    }
    return result.notificationID;
  }
}
