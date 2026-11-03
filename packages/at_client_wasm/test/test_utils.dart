import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

AtKeys legacyAtKeys({Atsign? atsign}) {
  String b64(String value) => base64Encode(utf8.encode(value));
  return AtKeys(atsign: atsign)
    ..fileLegacyMaterial(
      apkamPublicKey: b64('testApkamPublicKey'),
      apkamPrivateKey: b64('testApkamPrivateKey'),
      encryptionPublicKey: b64('defaultEncryptionPublicKey'),
      encryptionPrivateKey: b64('defaultEncryptionPrivateKey'),
      selfEncryptionKey: b64('defaultSelfEncryptionKey'),
      apkamSymmetricKey: b64('apkamSymmetricKey'),
      enrollmentId: '352b78c8-4b6f-4d07-a9cf-5466512ffa44',
    );
}

final _defaultCreatedAt = DateTime.utc(2024, 1, 1);

CryptographicMaterial symmetricKey(
  String keyId, {
  String value = 'c2VjcmV0',
  CryptographicMaterialAlgorithm algorithm =
      CryptographicMaterialAlgorithm.aes256,
  List<String> operations = const [],
  String? enrollmentId,
  DateTime? createdAt,
}) {
  return CryptographicMaterial(
    keyId: keyId,
    enrollmentId: enrollmentId,
    role: CryptographicMaterialRole.symmetricEncryption,
    algorithm: algorithm,
    bytes: AtBytes.fromString(value),
    operations: operations,
    createdAt: createdAt ?? _defaultCreatedAt,
  );
}

List<CryptographicMaterial> rsaKeyPair(
  String keyId, {
  String publicValue = 'cHVibGlj',
  String privateValue = 'cHJpdmF0ZQ==',
  String? enrollmentId,
  DateTime? createdAt,
}) {
  final at = createdAt ?? _defaultCreatedAt;
  return [
    CryptographicMaterial(
      keyId: keyId,
      enrollmentId: enrollmentId,
      role: CryptographicMaterialRole.publicEncryption,
      algorithm: CryptographicMaterialAlgorithm.rsa2048,
      bytes: AtBytes.fromString(publicValue),
      createdAt: at,
    ),
    CryptographicMaterial(
      keyId: keyId,
      enrollmentId: enrollmentId,
      role: CryptographicMaterialRole.privateDecryption,
      algorithm: CryptographicMaterialAlgorithm.rsa2048,
      bytes: AtBytes.fromString(privateValue),
      createdAt: at,
    ),
  ];
}

void expectLegacyAtKeys(AtKeys actual, AtKeys expected) {
  expect(actual.toJson(), expected.toJson());
}
