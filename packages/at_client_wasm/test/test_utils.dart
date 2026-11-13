// ignore_for_file: deprecated_member_use
// The fixtures build legacy flat-field keyfiles on purpose.
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';

AtKeys classicalAtKeys({Atsign? atsign}) {
  return AtKeys(atsign: atsign)
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

/// [classicalAtKeys] plus an ML-DSA-65 data signing key under the enrollment
/// the keys authenticate as.
AtKeys mlDsaSigningAtKeys({Atsign? atsign}) {
  final keys = classicalAtKeys(atsign: atsign);
  keys.fileSigningMaterial(
      enrollmentId: keys.enrollmentToAuthenticateAs(),
      algorithm: CryptographicMaterialAlgorithm.mlDsa65,
      publicKey: base64Encode(utf8.encode('mlDsaPublic')),
      privateKey: base64Encode(utf8.encode('mlDsaPrivate')));
  return keys;
}

/// [classicalAtKeys] plus a private namespace key.
AtKeys nskeyAtKeys({Atsign? atsign}) {
  final keys = classicalAtKeys(atsign: atsign);
  keys.addKey(CryptographicMaterial(
      keyId: 'nskey.wavi.1',
      role: CryptographicMaterialRole.privateDecapsulation,
      algorithm: CryptographicMaterialAlgorithm.mlKem1024,
      bytes: AtBytes.fromString(base64Encode(utf8.encode('nskeySeed'))),
      createdAt: DateTime.utc(2024, 1, 1)));
  return keys;
}
