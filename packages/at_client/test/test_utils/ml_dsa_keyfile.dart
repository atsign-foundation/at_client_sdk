import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show RsaKeyPair;
import 'package:at_commons/at_commons.dart';

/// The self-encryption key [typedKeyfile] files unless told otherwise.
const String testSelfEncryptionKey =
    'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';

/// The halves of the atSign encryption keypair [typedKeyfile] files, so a
/// test can assert on what a client resolved without repeating the literal.
const String testEncryptionPublicKey = 'dGVzdC1lbmMtcHVibGlj';
const String testEncryptionPrivateKey = 'dGVzdC1lbmMtcHJpdmF0ZQ==';

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
          testEncryptionPublicKey))
      ..addKey(atSignKey('enc:rsa2048:1', 'privateDecryption', 'rsa2048',
          testEncryptionPrivateKey))
      ..addKey(atSignKey(
          'self:aes256:1', 'symmetricEncryption', 'aes256', selfEncryptionKey));
  }
  final io = InMemoryAtKeysIo();
  await io.write(atSign, keys);
  return io;
}

/// Files REAL material for [atSign] as typed keys — its RSA
/// [encryptionKeyPair], its [selfEncryptionKey], and an rsa2048 APKAM
/// [apkamKeyPair] for [enrollmentId] when both are given — into [io], or a
/// fresh in-memory source, and returns it.
///
/// The typed form of what a test used to hand a client as an `AtChops`: a
/// client built on the result encrypts, decrypts and signs with these keys,
/// and nothing here names a deprecated member. Material already in [io] is
/// kept.
Future<InMemoryAtKeysIo> keyfileHolding(
  String atSign, {
  RsaKeyPair? encryptionKeyPair,
  String? selfEncryptionKey,
  String? enrollmentId,
  RsaKeyPair? apkamKeyPair,
  InMemoryAtKeysIo? io,
}) async {
  final target = io ?? InMemoryAtKeysIo();
  AtKeys keys;
  try {
    keys = await target.read(atSign);
  } on Object {
    keys = AtKeys();
  }
  final now = DateTime.now().toUtc();
  if (encryptionKeyPair != null) {
    keys
      ..addKey(CryptographicMaterial(
          keyId: 'enc:rsa2048:1',
          role: CryptographicMaterialRole.publicEncryption,
          algorithm: CryptographicMaterialAlgorithm.rsa2048,
          bytes: AtBytes.fromString(encryptionKeyPair.atPublicKey.publicKey),
          createdAt: now))
      ..addKey(CryptographicMaterial(
          keyId: 'enc:rsa2048:1',
          role: CryptographicMaterialRole.privateDecryption,
          algorithm: CryptographicMaterialAlgorithm.rsa2048,
          bytes: AtBytes.fromString(encryptionKeyPair.atPrivateKey.privateKey),
          createdAt: now));
  }
  if (selfEncryptionKey != null) {
    keys.addKey(CryptographicMaterial(
        keyId: 'self:aes256:1',
        role: CryptographicMaterialRole.symmetricEncryption,
        algorithm: CryptographicMaterialAlgorithm.aes256,
        bytes: AtBytes.fromString(selfEncryptionKey),
        createdAt: now));
  }
  if (enrollmentId != null && apkamKeyPair != null) {
    keys.fileApkamMaterial(
        enrollmentId: enrollmentId,
        algorithm: CryptographicMaterialAlgorithm.rsa2048,
        publicKey: apkamKeyPair.atPublicKey.publicKey,
        privateKey: apkamKeyPair.atPrivateKey.privateKey);
  }
  await target.write(atSign, keys);
  return target;
}

/// A key source holding [atSign]'s APKAM [keyPair]: typed rsa2048 material
/// under [enrollmentId] when one is named, the flat legacy pair otherwise.
///
/// The typed form of the AtChops a test used to hand a mock client so that
/// it could sign; `ApkamSigning` reads the keypair from here.
InMemoryAtKeysIo keysHoldingApkam(
    String atSign, String? enrollmentId, RsaKeyPair keyPair) {
  final keys = AtKeys(atsign: atSign.toAtsign());
  if (enrollmentId == null) {
    keys.fileLegacyMaterial(
        apkamPublicKey: keyPair.atPublicKey.publicKey,
        apkamPrivateKey: keyPair.atPrivateKey.privateKey);
  } else {
    keys.fileApkamMaterial(
        enrollmentId: enrollmentId,
        algorithm: CryptographicMaterialAlgorithm.rsa2048,
        publicKey: keyPair.atPublicKey.publicKey,
        privateKey: keyPair.atPrivateKey.privateKey);
  }
  return InMemoryAtKeysIo.holding(atSign, keys);
}

/// A keyfile whose [enrollmentId] has active typed ML-DSA **authentication**
/// material, and nothing else.
///
/// The narrower shape [typedKeyfile] produces with `withAtSignKeys: false`:
/// what `signingAlgorithmForEnrollment` reads is the authentication role, and
/// these callers assert on that alone.
Future<InMemoryAtKeysIo> mlDsaKeyfile(String atSign, String enrollmentId) =>
    typedKeyfile(atSign, enrollmentId: enrollmentId, withAtSignKeys: false);
