part of '../isolated_atclient.dart';

class _IsolatedAtClient implements IsolatedAtClient {
  final Stream _recv;
  final void Function() _closeRecv;
  final SendPort _send;
  final String _atSign;
  final Mutex _mutex = Mutex();

  _IsolatedAtClient({
    required Stream<Object?> recv,
    required void Function() closeRecv,
    required SendPort send,
    required String atSign,
  })  : _recv = recv,
        _closeRecv = closeRecv,
        _send = send,
        _atSign = atSign;

  @override
  void close() {
    _send.send((request: "close", params: ()));
    _closeRecv();
  }

  // BEGIN SECTION: AtClient API
  @override
  Future<bool> delete(AtKey key,
      {bool isDedicated = false,
      DeleteRequestOptions? deleteRequestOptions}) async {
    _DeleteRequest params = (
      atKey: _atKeyToRecord(key),
      isDedicated: isDedicated,
      useRemoteAtServer: deleteRequestOptions?.useRemoteAtServer
    );
    _WorkerRequest<_DeleteRequest> req = (request: "delete", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _DeleteResponse) {
        throw result;
      }
      return result.success;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<AtValue> get(AtKey key,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions}) async {
    _GetRequest params = (
      atKey: _atKeyToRecord(key),
      isDedicated: isDedicated,
      bypassCache: getRequestOptions?.bypassCache,
      useRemoteAtServer: getRequestOptions?.useRemoteAtServer
    );
    _WorkerRequest<_GetRequest> req = (request: "get", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _GetResponse) {
        throw result;
      }
      return AtValue()
        ..value = result.value
        ..metadata = result.metadata != null
            ? _metadataFromRecord(result.metadata!)
            : null;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<List<AtKey>> getAtKeys(
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool showHiddenKeys = false,
      bool useRemoteAtServer = false}) async {
    _GetAtKeysRequest params = (
      regex: regex,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      showHiddenKeys: showHiddenKeys,
      useRemoteAtServer: useRemoteAtServer
    );
    _WorkerRequest<_GetAtKeysRequest> req =
        (request: "getAtKeys", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _GetAtKeysResponse) {
        throw result;
      }
      return result.atKeys.map((key) => AtKey.fromString(key)).toList();
    } finally {
      _mutex.release();
    }
  }

  @override
  String? getCurrentAtSign() => _atSign;

  @override
  Future<List<String>> getKeys(
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool showHiddenKeys = false,
      bool useRemoteAtServer = false}) async {
    _GetKeysRequest params = (
      regex: regex,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      showHiddenKeys: showHiddenKeys,
      useRemoteAtServer: useRemoteAtServer
    );
    _WorkerRequest<_GetKeysRequest> req = (request: "getKeys", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _GetKeysResponse) {
        throw result;
      }
      return result.keys;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<Metadata?> getMeta(AtKey key) async {
    _GetMetaRequest params = (atKey: _atKeyToRecord(key));
    _WorkerRequest<_GetMetaRequest> req = (request: "getMeta", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _GetMetaResponse) {
        throw result;
      }
      return result.metadata != null
          ? _metadataFromRecord(result.metadata!)
          : null;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<AtResponse> getOTP() async {
    _WorkerRequest<void> req = (request: "getOTP", params: null);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _GetOTPResponse) {
        throw result;
      }
      return AtResponse().fromJson(result.atResponse);
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<String> notifyList(
      {String? fromDate, String? toDate, String? regex}) async {
    _NotifyListRequest params =
        (fromDate: fromDate, toDate: toDate, regex: regex);
    _WorkerRequest<_NotifyListRequest> req =
        (request: "notifyList", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _NotifyListResponse) {
        throw result;
      }
      return result.result;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<String> notifyStatus(String notificationId) async {
    _NotifyStatusRequest params = (notificationId: notificationId);
    _WorkerRequest<_NotifyStatusRequest> req =
        (request: "notifyStatus", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _NotifyStatusResponse) {
        throw result;
      }
      return result.status;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<bool> put(AtKey key, value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    _PutRequest params = (
      atKey: _atKeyToRecord(key),
      value: value,
      isDedicated: isDedicated,
      storeSharedKeyEncryptedMetadata:
          putRequestOptions?.storeSharedKeyEncryptedMetadata,
      useRemoteAtServer: putRequestOptions?.useRemoteAtServer,
      shouldEncrypt: putRequestOptions?.shouldEncrypt
    );
    _WorkerRequest<_PutRequest> req = (request: "put", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _PutResponse) {
        throw result;
      }
      return result.success;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<AtResponse> putBinary(AtKey atKey, List<int> value,
      {PutRequestOptions? putRequestOptions}) async {
    _PutBinaryRequest params = (
      atKey: _atKeyToRecord(atKey),
      value: value,
      storeSharedKeyEncryptedMetadata:
          putRequestOptions?.storeSharedKeyEncryptedMetadata,
      useRemoteAtServer: putRequestOptions?.useRemoteAtServer,
      shouldEncrypt: putRequestOptions?.shouldEncrypt
    );
    _WorkerRequest<_PutBinaryRequest> req =
        (request: "putBinary", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _PutBinaryResponse) {
        throw result;
      }
      return AtResponse().fromJson(result.atResponse);
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<bool> putMeta(AtKey key) async {
    _PutMetaRequest params = (atKey: _atKeyToRecord(key));
    _WorkerRequest<_PutMetaRequest> req = (request: "putMeta", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _PutMetaResponse) {
        throw result;
      }
      return result.success;
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<AtResponse> putText(AtKey atKey, String value,
      {PutRequestOptions? putRequestOptions}) async {
    _PutTextRequest params = (
      atKey: _atKeyToRecord(atKey),
      value: value,
      storeSharedKeyEncryptedMetadata:
          putRequestOptions?.storeSharedKeyEncryptedMetadata,
      useRemoteAtServer: putRequestOptions?.useRemoteAtServer,
      shouldEncrypt: putRequestOptions?.shouldEncrypt
    );
    _WorkerRequest<_PutTextRequest> req = (request: "putText", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _PutTextResponse) {
        throw result;
      }
      return AtResponse().fromJson(result.atResponse);
    } finally {
      _mutex.release();
    }
  }

  @override
  Future<AtResponse> setSPP(String otp) async {
    _SetSPPRequest params = (otp: otp);
    _WorkerRequest<_SetSPPRequest> req = (request: "setSPP", params: params);
    await _mutex.acquire();
    try {
      _send.send(req);
      var result = await _recv.take(1).single;
      if (result is! _SetSPPResponse) {
        throw result;
      }
      return AtResponse().fromJson(result.atResponse);
    } finally {
      _mutex.release();
    }
  }
  // END SECTION: AtClient API

  // BEGIN SECTION: UTILITY

  // Helper function to convert AtKey to _AtKeyRecord
  _AtKeyRecord _atKeyToRecord(AtKey atKey) {
    return (
      key: atKey.key,
      sharedWith: atKey.sharedWith,
      sharedBy: atKey.sharedBy,
      namespace: atKey.namespace,
      isLocal: atKey.isLocal,
      isRef: atKey.isRef,
      metadata: _metadataToRecord(atKey.metadata),
    );
  }

  // Helper function to convert Metadata to _MetadataRecord
  _MetadataRecord _metadataToRecord(Metadata metadata) {
    return (
      ttl: metadata.ttl,
      ttb: metadata.ttb,
      ttr: metadata.ttr,
      ccd: metadata.ccd,
      availableAt: metadata.availableAt,
      expiresAt: metadata.expiresAt,
      refreshAt: metadata.refreshAt,
      createdAt: metadata.createdAt,
      updatedAt: metadata.updatedAt,
      dataSignature: metadata.dataSignature,
      sharedKeyStatus: metadata.sharedKeyStatus,
      isPublic: metadata.isPublic,
      isHidden: metadata.isHidden,
    );
  }

  // Helper function to convert _MetadataRecord to Metadata
  Metadata _metadataFromRecord(_MetadataRecord record) {
    return Metadata()
      ..ttl = record.ttl
      ..ttb = record.ttb
      ..ttr = record.ttr
      ..ccd = record.ccd
      ..availableAt = record.availableAt
      ..expiresAt = record.expiresAt
      ..refreshAt = record.refreshAt
      ..createdAt = record.createdAt
      ..updatedAt = record.updatedAt
      ..dataSignature = record.dataSignature
      ..sharedKeyStatus = record.sharedKeyStatus
      ..isPublic = record.isPublic
      ..isHidden = record.isHidden;
  }
  // END SECTION: UTILITY

  // BEGIN SECTION: UNIMPLEMENTED
  // Implementing these may be useful, but not worth the effort unless there's
  // a clear need.

  @override
  void setPreferences(AtClientPreference preference) =>
      throw UnimplementedError();

  @override
  AtClientPreference? getPreferences() => throw UnimplementedError();

  @override
  LocalSecondary? getLocalSecondary() => throw UnimplementedError();
  @override
  RemoteSecondary? getRemoteSecondary() => throw UnimplementedError();

  @override
  EncryptionService? get encryptionService => throw UnimplementedError();

  @override
  AtChops? get atChops => throw UnimplementedError();

  @override
  String? get enrollmentId => throw UnimplementedError();

  @override
  EnrollmentService? get enrollmentService => throw UnimplementedError();

  @override
  NotificationService get notificationService => throw UnimplementedError();

  @override
  SyncService get syncService => throw UnimplementedError();

  @override
  AtTelemetryService? get telemetry => throw UnimplementedError();

  @override
  set atChops(AtChops? atChops) => throw UnimplementedError();

  @override
  set enrollmentId(String? enrollmentId) => throw UnimplementedError();

  @override
  set enrollmentService(EnrollmentService? enrollmentService) =>
      throw UnimplementedError();

  @override
  set notificationService(NotificationService notificationService) =>
      throw UnimplementedError();

  @override
  set syncService(SyncService syncService) => throw UnimplementedError();

  @override
  set telemetry(AtTelemetryService? telemetryService) =>
      throw UnimplementedError();

  @override
  Future<void> startCompactionJob({Duration? commitLogCompactionDuration}) =>
      throw UnimplementedError();

  @override
  Future<void> stopCompactionJob() => throw UnimplementedError();
  // END SECTION: UNIMPLEMENTED

  // BEGIN SECTION: DEPRECATED MEMBERS
  // No point in implementing deprecated members of AtClient
  // for a new implementation.
  // This implementation does not need to be a drop-in replacement,
  // but rather, only forwards compatible for new projects.
  @override
  // ignore: deprecated_member_use
  SyncManager? getSyncManager() => throw UnimplementedError();

  @override
  Future<bool> notify(AtKey key, String value, OperationEnum operation,
          {MessageTypeEnum? messageType,
          PriorityEnum? priority,
          StrategyEnum? strategy,
          int? latestN,
          String? notifier,
          bool isDedicated = false}) =>
      throw UnimplementedError();

  @override
  Future<String?> notifyChange(NotificationParams notificationParams) =>
      throw UnimplementedError();
  @override
  Future<String> notifyAll(
          AtKey atKey, String value, OperationEnum operation) =>
      throw UnimplementedError();

  @override
  Future<void> startMonitor(String privateKey, Function acceptStream,
          {String? regex}) =>
      throw UnimplementedError();

  @override
  Future<AtStreamResponse> stream(String sharedWith, String filePath,
          {String namespace = ""}) =>
      throw UnimplementedError();

  @override
  Future<void> sendStreamAck(
          String streamId,
          String fileName,
          int fileLength,
          String senderAtSign,
          Function streamCompletionCallBack,
          Function streamReceiveCallBack) =>
      throw UnimplementedError();

  @override
  Future<Map<String, FileTransferObject>> uploadFile(
          List<File> files, List<String> sharedWithAtSigns) =>
      throw UnimplementedError();

  @override
  Future<List<File>> downloadFile(String transferId, String sharedByAtSign,
          {String? downloadPath}) =>
      throw UnimplementedError();

  @override
  Future<List<FileStatus>> reuploadFiles(
          List<File> files, FileTransferObject fileTransferObject) =>
      throw UnimplementedError();

  @override
  Future<Map<String, FileTransferObject>> shareFiles(
          List<String> sharedWithAtSigns,
          String key,
          String fileUrl,
          String encryptionKey,
          List<FileStatus> fileStatus,
          {DateTime? date}) =>
      throw UnimplementedError();

  // END SECTION: DEPRECATED MEMBERS
}
