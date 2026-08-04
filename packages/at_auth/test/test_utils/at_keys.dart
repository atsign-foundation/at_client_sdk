import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

AtKeys legacyAtKeys({Atsign? atsign}) {
  return AtKeys(atsign: atsign ?? '@alice'.toAtsign())
    ..apkamPublicKey =
        AtBytes.fromString(base64Encode(utf8.encode('testApkamPublicKey')))
    ..apkamPrivateKey =
        AtBytes.fromString(base64Encode(utf8.encode('testApkamPrivateKey')))
    ..defaultEncryptionPublicKey = AtBytes.fromString(
        base64Encode(utf8.encode('defaultEncryptionPublicKey')))
    ..defaultEncryptionPrivateKey = AtBytes.fromString(
        base64Encode(utf8.encode('defaultEncryptionPrivateKey')))
    ..defaultSelfEncryptionKey = AtBytes.fromString(
        base64Encode(utf8.encode('defaultSelfEncryptionKey')))
    ..apkamSymmetricKey =
        AtBytes.fromString(base64Encode(utf8.encode('apkamSymmetricKey')))
    ..enrollmentId = '352b78c8-4b6f-4d07-a9cf-5466512ffa44';
}

final _defaultCreatedAt = DateTime.utc(2024, 1, 1);

AtKeysMaterial symmetricKey(
  String keyId, {
  String value = 'c2VjcmV0',
  String algorithm = KeyAlgorithmType.aes256,
  List<String> operations = const [],
  DateTime? createdAt,
}) {
  return AtKeysMaterial(
    keyId: keyId,
    keyPartType: CryptographicKeyType.symmetricEncryption,
    keyAlgorithmType: algorithm,
    bytes: base64Decode(value),
    operations: operations,
    createdAt: createdAt ?? _defaultCreatedAt,
  );
}

/// The public+private halves of one RSA keypair sharing [keyId] — spread
/// this into a `keysList` (`[...rsaKeyPair('id')]`) since it's two materials.
List<AtKeysMaterial> rsaKeyPair(
  String keyId, {
  String publicValue = 'cHVibGlj',
  String privateValue = 'cHJpdmF0ZQ==',
  DateTime? createdAt,
}) {
  final at = createdAt ?? _defaultCreatedAt;
  return [
    AtKeysMaterial(
      keyId: keyId,
      keyPartType: CryptographicKeyType.publicEncryption,
      keyAlgorithmType: KeyAlgorithmType.rsa2048,
      bytes: base64Decode(publicValue),
      createdAt: at,
    ),
    AtKeysMaterial(
      keyId: keyId,
      keyPartType: CryptographicKeyType.privateDecryption,
      keyAlgorithmType: KeyAlgorithmType.rsa2048,
      bytes: base64Decode(privateValue),
      createdAt: at,
    ),
  ];
}

void expectLegacyAtKeys(AtKeys actual, AtKeys expected) {
  expect(
    actual.apkamPrivateKey.toString(),
    expected.apkamPrivateKey.toString(),
  );
  expect(actual.apkamPublicKey.toString(), expected.apkamPublicKey.toString());
  expect(
    actual.apkamSymmetricKey.toString(),
    expected.apkamSymmetricKey.toString(),
  );
  expect(
    actual.defaultEncryptionPrivateKey.toString(),
    expected.defaultEncryptionPrivateKey.toString(),
  );
  expect(
    actual.defaultEncryptionPublicKey.toString(),
    expected.defaultEncryptionPublicKey.toString(),
  );
  expect(
    actual.defaultSelfEncryptionKey.toString(),
    expected.defaultSelfEncryptionKey.toString(),
  );
  expect(actual.enrollmentId, expected.enrollmentId);
}
