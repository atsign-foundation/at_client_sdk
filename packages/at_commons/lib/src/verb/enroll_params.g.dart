// GENERATED CODE - DO NOT MODIFY BY HAND
// dart run build_runner build - to generate this file
// After generating, revert changes for apkamKeysExpiryInMillis since value has to be in milliseconds

part of 'enroll_params.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EnrollParams _$EnrollParamsFromJson(Map<String, dynamic> json) => EnrollParams()
  ..enrollmentId = json['enrollmentId'] as String?
  ..appName = json['appName'] as String?
  ..deviceName = json['deviceName'] as String?
  ..namespaces = (json['namespaces'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  )
  ..otp = json['otp'] as String?
  ..encryptedDefaultEncryptionPrivateKey =
      json['encryptedDefaultEncryptionPrivateKey'] as String?
  ..encPrivateKeyIV = json['encPrivateKeyIV'] as String?
  ..encryptedDefaultSelfEncryptionKey =
      json['encryptedDefaultSelfEncryptionKey'] as String?
  ..selfEncKeyIV = json['selfEncKeyIV'] as String?
  ..encryptedAPKAMSymmetricKey = json['encryptedAPKAMSymmetricKey'] as String?
  ..apkamPublicKey = json['apkamPublicKey'] as String?
  ..enrollmentStatusFilter = (json['enrollmentStatusFilter'] as List<dynamic>?)
      ?.map((e) => $enumDecode(_$EnrollmentStatusEnumMap, e))
      .toList()
  ..apkamKeysExpiryDuration = json['apkamKeysExpiryInMillis'] == null
      ? null
      : Duration(milliseconds: json['apkamKeysExpiryInMillis']);

Map<String, dynamic> _$EnrollParamsToJson(EnrollParams instance) =>
    <String, dynamic>{
      'enrollmentId': instance.enrollmentId,
      'appName': instance.appName,
      'deviceName': instance.deviceName,
      'namespaces': instance.namespaces,
      'otp': instance.otp,
      'encryptedDefaultEncryptionPrivateKey':
          instance.encryptedDefaultEncryptionPrivateKey,
      'encPrivateKeyIV': instance.encPrivateKeyIV,
      'encryptedDefaultSelfEncryptionKey':
          instance.encryptedDefaultSelfEncryptionKey,
      'selfEncKeyIV': instance.selfEncKeyIV,
      'encryptedAPKAMSymmetricKey': instance.encryptedAPKAMSymmetricKey,
      'apkamPublicKey': instance.apkamPublicKey,
      'enrollmentStatusFilter': instance.enrollmentStatusFilter
          ?.map((e) => _$EnrollmentStatusEnumMap[e]!)
          .toList(),
      'apkamKeysExpiryInMillis':
          instance.apkamKeysExpiryDuration?.inMilliseconds,
    };

const _$EnrollmentStatusEnumMap = {
  EnrollmentStatus.pending: 'pending',
  EnrollmentStatus.approved: 'approved',
  EnrollmentStatus.denied: 'denied',
  EnrollmentStatus.revoked: 'revoked',
  EnrollmentStatus.expired: 'expired',
};
