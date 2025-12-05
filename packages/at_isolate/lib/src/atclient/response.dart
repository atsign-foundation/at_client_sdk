part of '../isolated_atclient.dart';

// Response typedefs for isolate communication
// AtKey is serialized using toString() and deserialized using fromString()
// AtResponse is serialized using toJson() and deserialized using fromJson()
typedef _WorkerRequest<T> = ({String request, T params});

/// Response for delete operation
typedef _DeleteResponse = ({
  bool success,
});

/// Response for get operation
typedef _GetResponse = ({
  Object? value,
  _MetadataRecord? metadata,
});

/// Response for getAtKeys operation
typedef _GetAtKeysResponse = ({
  List<String> atKeys, // Serialized using AtKey.toString()
});

/// Response for getKeys operation
typedef _GetKeysResponse = ({
  List<String> keys,
});

/// Response for getMeta operation
typedef _GetMetaResponse = ({
  _MetadataRecord? metadata,
});

/// Response for getOTP operation
typedef _GetOTPResponse = ({
  Map<String, dynamic> atResponse, // AtResponse.toJson()
});

/// Response for getPreferences operation - left as is for now
// typedef _GetPreferencesResponse = ({
//   AtClientPreference? preferences,
// });

/// Response for notifyList operation
typedef _NotifyListResponse = ({
  String result,
});

/// Response for notifyStatus operation
typedef _NotifyStatusResponse = ({
  String status,
});

/// Response for put operation
typedef _PutResponse = ({
  bool success,
});

/// Response for putBinary operation
typedef _PutBinaryResponse = ({
  Map<String, dynamic> atResponse, // AtResponse.toJson()
});

/// Response for putMeta operation
typedef _PutMetaResponse = ({
  bool success,
});

/// Response for putText operation
typedef _PutTextResponse = ({
  Map<String, dynamic> atResponse, // AtResponse.toJson()
});

/// Response for setSPP operation
typedef _SetSPPResponse = ({
  Map<String, dynamic> atResponse, // AtResponse.toJson()
});
