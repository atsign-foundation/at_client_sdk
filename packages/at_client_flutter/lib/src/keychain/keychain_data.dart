import 'package:at_auth/at_auth.dart' show AtKeys;

sealed class KeychainData {
  KeychainData();
  Map<String, dynamic> toJson() {
    return {};
  }
}

class EmptyKeychainData extends KeychainData {
  EmptyKeychainData();
}

class AtKeysData extends KeychainData {
  List<AtKeys> keys;
  String? defaultAtsign;
  AtKeysData({
    this.keys = const [],
    this.defaultAtsign,
  });

  factory AtKeysData.fromJson(Map<String, dynamic> json) => AtKeysData(
        keys: (json['keys'] as List<dynamic>?)
                ?.map((e) => AtKeys.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        defaultAtsign: json['defaultAtsign'],
      );

  @override
  Map<String, dynamic> toJson() => {
        'keys': keys,
        'defaultAtsign': defaultAtsign,
      };
}

class EnrollmentData extends KeychainData {
  String enrollmentId;
  AtKeys atAuthKeys;
  int enrollmentSubmissionTimeEpoch;
  Map<String, dynamic>? namespace;
  String? keysFilePath;

  EnrollmentData(
    this.enrollmentId,
    this.atAuthKeys,
    this.enrollmentSubmissionTimeEpoch, {
    this.namespace,
    this.keysFilePath,
  });

  factory EnrollmentData.fromJson(Map<String, dynamic> json) => EnrollmentData(
        json['enrollmentId'] as String,
        AtKeys.fromJson(json['atAuthKeys'] as Map<String, dynamic>),
        json['enrollmentSubmissionTimeEpoch'] as int,
        namespace: json['namespace'] as Map<String, dynamic>?,
        keysFilePath: json['keysFilePath'] as String?,
      );

  @override
  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'atAuthKeys': atAuthKeys.toJson(),
      'enrollmentSubmissionTimeEpoch': enrollmentSubmissionTimeEpoch,
      'namespace': namespace,
      'keysFilePath': keysFilePath
    };
  }
}
