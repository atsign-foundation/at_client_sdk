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
  List<EnrollmentStatus>? enrollmentStatusFilter;
  Duration? apkamKeysExpiryDuration;

  EnrollParams();

  factory EnrollParams.fromJson(Map<String, dynamic> json) =>
      _$EnrollParamsFromJson(json);

  Map<String, dynamic> toJson() => _$EnrollParamsToJson(this);
}
