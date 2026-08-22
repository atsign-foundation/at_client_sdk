import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';

/// A keyfile whose [enrollmentId] has active typed ML-DSA **authentication**
/// material.
///
/// Authentication rather than signing because PKAM proves possession of the
/// APKAM keypair, and that keypair is no longer the same thing as the
/// enrollment's attestation signing keys — `signingAlgorithmForEnrollment`
/// reads the authentication role for exactly that reason.
Future<InMemoryAtKeysIo> mlDsaKeyfile(
    String atSign, String enrollmentId) async {
  final now = DateTime.now().toUtc();
  final keys = AtKeys()
    ..addKey(CryptographicMaterial(
      keyId: 'apkam:$enrollmentId:1',
      enrollmentId: enrollmentId,
      keyPartType: CryptographicMaterialRole.privateAuthentication,
      keyAlgorithmType: CryptographicMaterialAlgorithm.mlDsa65,
      bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 3))),
      createdAt: now,
    ))
    ..addKey(CryptographicMaterial(
      keyId: 'apkam:$enrollmentId:1',
      enrollmentId: enrollmentId,
      keyPartType: CryptographicMaterialRole.publicAuthentication,
      keyAlgorithmType: CryptographicMaterialAlgorithm.mlDsa65,
      bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 4))),
      createdAt: now,
    ));
  final io = InMemoryAtKeysIo();
  await io.write(atSign, keys);
  return io;
}
