import 'package:at_auth/at_auth.dart';

/// Class representing the enrollment details to store in the keychain.
/// When an enrollment is submitted successfully, the APKAM keys pair are stored the keychain to persist the data incase
/// of an app closure. When an enrollment is approved, the key pairs are fetches and .atKeys file is generated.
class EnrollmentInfo {
  String enrollmentId;
  AtAuthKeys atAuthKeys;
  int enrollmentSubmissionTimeEpoch;
  Map<String, dynamic>? namespace;
  String? keysFilePath;

  EnrollmentInfo(
    this.enrollmentId,
    this.atAuthKeys,
    this.enrollmentSubmissionTimeEpoch,
    this.namespace,
  );

  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'atAuthKeys': atAuthKeys.toJson(),
      'enrollmentSubmissionTimeEpoch': enrollmentSubmissionTimeEpoch,
      'namespace': namespace
    };
  }

  EnrollmentInfo.fromJson(Map<String, dynamic> json)
      : enrollmentId = json['enrollmentId'],
        atAuthKeys = AtAuthKeys.fromJson(json['atAuthKeys']),
        enrollmentSubmissionTimeEpoch = json['enrollmentSubmissionTimeEpoch'],
        namespace = json['namespace'];
}
