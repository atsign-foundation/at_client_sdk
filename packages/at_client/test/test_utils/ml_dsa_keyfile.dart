import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';

/// The self-encryption key [typedKeyfile] files unless told otherwise.
const String testSelfEncryptionKey =
    'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';

/// A keyfile for [atSign] carrying **typed material only**, so a test can
/// build its keys without naming a deprecated member.
///
/// This is how production hands a client its keys, and the only route from an
/// `AtKeysIo` to a client's crypto: pass the result as
/// `AtClientImpl.create(atSign, namespace, preference, atKeysIo: …)` and the
/// client derives its own `AtChops` from what is filed here. Injecting an
/// `AtChops` instead reaches the same place through the deprecated door.
///
/// [enrollmentId] gets an active APKAM **authentication** keypair in
/// [algorithm] — authentication rather than signing because PKAM proves
/// possession of the APKAM keypair, which is distinct from the enrollment's
/// attestation signing keys. Unless [withAtSignKeys] is false, the atSign also
/// gets its own RSA encryption keypair and a symmetric self-encryption key,
/// which are what the derived `AtChops` encrypts and decrypts with.
///
/// The bytes are stand-ins, not real keys: nothing parses them until a cipher
/// is actually run, so a test that only needs a client to hold key material
/// does not have to generate any. A test that encrypts needs real material.
Future<InMemoryAtKeysIo> typedKeyfile(
  String atSign, {
  String enrollmentId = 'test-enrollment',
  CryptographicMaterialAlgorithm algorithm =
      CryptographicMaterialAlgorithm.mlDsa65,
  String selfEncryptionKey = testSelfEncryptionKey,
  bool withAtSignKeys = true,
}) async {
  final now = DateTime.now().toUtc();
  CryptographicMaterial apkam(String role, int fill) => CryptographicMaterial(
        keyId: 'apkam:$enrollmentId:1',
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.of(role),
        algorithm: algorithm,
        bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, fill))),
        createdAt: now,
      );
  CryptographicMaterial atSignKey(
          String keyId, String role, String algo, String bytes) =>
      CryptographicMaterial(
        keyId: keyId,
        role: CryptographicMaterialRole.of(role),
        algorithm: CryptographicMaterialAlgorithm.of(algo),
        bytes: AtBytes.fromString(bytes),
        createdAt: now,
      );

  final keys = AtKeys()
    ..addKey(apkam('privateAuthentication', 3))
    ..addKey(apkam('publicAuthentication', 4));
  if (withAtSignKeys) {
    keys
      ..addKey(atSignKey('enc:rsa2048:1', 'publicEncryption', 'rsa2048',
          'dGVzdC1lbmMtcHVibGlj'))
      ..addKey(atSignKey('enc:rsa2048:1', 'privateDecryption', 'rsa2048',
          'dGVzdC1lbmMtcHJpdmF0ZQ=='))
      ..addKey(atSignKey(
          'self:aes256:1', 'symmetricEncryption', 'aes256', selfEncryptionKey));
  }
  final io = InMemoryAtKeysIo();
  await io.write(atSign, keys);
  return io;
}

/// A keyfile whose [enrollmentId] has active typed ML-DSA **authentication**
/// material, and nothing else.
///
/// The narrower shape [typedKeyfile] produces with `withAtSignKeys: false`:
/// what `signingAlgorithmForEnrollment` reads is the authentication role, and
/// these callers assert on that alone.
Future<InMemoryAtKeysIo> mlDsaKeyfile(String atSign, String enrollmentId) =>
    typedKeyfile(atSign, enrollmentId: enrollmentId, withAtSignKeys: false);
