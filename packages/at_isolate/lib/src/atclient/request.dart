part of '../isolated_atclient.dart';

// Request typedefs for isolate communication
// AtKey is serialized using toString() and deserialized using fromString()

/// Request for delete operation
typedef _DeleteRequest = ({
  _AtKeyRecord atKey,
  bool isDedicated,
  bool? useRemoteAtServer,
});

/// Request for get operation
typedef _GetRequest = ({
  _AtKeyRecord atKey,
  bool isDedicated,
  bool? bypassCache,
  bool? useRemoteAtServer,
});

/// Request for getAtKeys operation
typedef _GetAtKeysRequest = ({
  String? regex,
  String? sharedBy,
  String? sharedWith,
  bool showHiddenKeys,
  bool useRemoteAtServer,
});

/// Request for getKeys operation
typedef _GetKeysRequest = ({
  String? regex,
  String? sharedBy,
  String? sharedWith,
  bool showHiddenKeys,
  bool useRemoteAtServer,
});

/// Request for getMeta operation
typedef _GetMetaRequest = ({
  _AtKeyRecord atKey,
});

/// Request for notifyList operation
typedef _NotifyListRequest = ({
  String? fromDate,
  String? toDate,
  String? regex,
});

/// Request for notifyStatus operation
typedef _NotifyStatusRequest = ({
  String notificationId,
});

/// Request for put operation
typedef _PutRequest = ({
  _AtKeyRecord atKey,
  dynamic value,
  bool isDedicated,
  bool? storeSharedKeyEncryptedMetadata,
  bool? useRemoteAtServer,
  bool? shouldEncrypt,
});

/// Request for putBinary operation
typedef _PutBinaryRequest = ({
  _AtKeyRecord atKey,
  List<int> value,
  bool? storeSharedKeyEncryptedMetadata,
  bool? useRemoteAtServer,
  bool? shouldEncrypt,
});

/// Request for putMeta operation
typedef _PutMetaRequest = ({
  _AtKeyRecord atKey,
});

/// Request for putText operation
typedef _PutTextRequest = ({
  _AtKeyRecord atKey,
  String value,
  bool? storeSharedKeyEncryptedMetadata,
  bool? useRemoteAtServer,
  bool? shouldEncrypt,
});

/// Request for setSPP operation
typedef _SetSPPRequest = ({
  String otp,
});

/// Metadata as a nested record
typedef _MetadataRecord = ({
  int? ttl,
  int? ttb,
  int? ttr,
  bool? ccd,
  DateTime? availableAt,
  DateTime? expiresAt,
  DateTime? refreshAt,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? dataSignature,
  String? sharedKeyStatus,
  bool isPublic,
  bool isHidden,
});

/// Full AtKey representation as a record for isolate communication
typedef _AtKeyRecord = ({
  // Core AtKey fields
  String key,
  String? sharedWith,
  String? sharedBy,
  String? namespace,
  bool isLocal,
  bool isRef,
  // Full metadata
  _MetadataRecord metadata,
});
