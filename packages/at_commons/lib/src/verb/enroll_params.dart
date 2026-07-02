import 'package:at_commons/at_commons.dart';
import 'package:json_annotation/json_annotation.dart';

part 'enroll_params.g.dart';

@JsonSerializable()
class EnrollParams {
  String? enrollmentId;
  String? appName;
  String? deviceName;
  Map<String, String>? namespaces;
  String? otp;
  String? encryptedDefaultEncryptionPrivateKey;
  String? encPrivateKeyIV;
  String? encryptedDefaultSelfEncryptionKey;
  String? selfEncKeyIV;
  String? encryptedAPKAMSymmetricKey;
  String? apkamPublicKey;

  /// The signing algorithm of [apkamPublicKey] — `rsa2048` (legacy default) or
  /// `mldsa65` (PQ). Recorded on the enrollment so PKAM verification is
  /// record-authoritative.
  String? signingAlgo;

  /// Opaque, additive metadata the server stores verbatim on the enrollment
  /// record and returns from discovery (`enroll:listns`). Carries the
  /// enrollment's key package (`metadata.keyPackages`) for the secret-sharing
  /// substrate; the server has no opinion on its contents.
  Map<String, dynamic>? metadata;

  List<EnrollmentStatus>? enrollmentStatusFilter;
  Duration? apkamKeysExpiryDuration;

  EnrollParams();

  factory EnrollParams.fromJson(Map<String, dynamic> json) =>
      _$EnrollParamsFromJson(json);

  Map<String, dynamic> toJson() => _$EnrollParamsToJson(this);
}
