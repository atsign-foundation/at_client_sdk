import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart' show AtBytes;

/// The key material a fresh atSign is activated with.
///
/// The APKAM keypair is handed back **beside** [keys] rather than inside it,
/// because where it belongs depends on the algorithm and is not known until
/// the atServer assigns an enrollment id:
///
/// - an `rsa2048` APKAM rides the flat `apkamPublicKey`/`apkamPrivateKey`
///   fields, which is what every published reader expects;
/// - an `mldsa65` APKAM is filed as typed material under `apkam:<enrollmentId>`
///   and the flat fields stay empty, so a reader that cannot handle it fails
///   loudly rather than signing with the wrong routine.
///
/// Either way the caller needs the raw halves before the enrollment exists —
/// the request advertises the public one, and the key-package builder signs
/// with the private one.
typedef OnboardingMint = ({
  AtKeys keys,
  String apkamPublicKey,
  String apkamPrivateKey,
});

/// Mints the key material for a first (CRAM) onboard.
///
/// [signingAlgo] picks the APKAM: `rsa2048` for a legacy activation,
/// `mldsa65` for a PQ-native one. The KEM key an enrollment advertises is not
/// minted here — it belongs to the key package, which is built against this
/// APKAM keypair by the request's `metadataBuilder`.
///
/// [mintLegacyMaterial] cuts the RSA encryption keypair, the
/// `selfEncryptionKey` and the `apkamSymmetricKey`. All three travel together
/// deliberately: the symmetric key exists to wrap the other two for conveyance
/// to a later enrollment, so minting it alone would produce a key with nothing
/// to wrap, and minting the pair without it would leave nothing able to convey
/// them.
Future<OnboardingMint> mintOnboardingKeys({
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  bool mintLegacyMaterial = true,
}) async {
  final keys = AtKeys();

  if (mintLegacyMaterial) {
    final encryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    keys
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(encryptionKeyPair.atPublicKey.publicKey.toString())
      ..defaultEncryptionPrivateKey = AtBytes.fromString(
          encryptionKeyPair.atPrivateKey.privateKey.toString())
      ..defaultSelfEncryptionKey = AtBytes.fromString(
          AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key)
      ..apkamSymmetricKey = AtBytes.fromString(
          AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key);
  }

  switch (signingAlgo) {
    case SigningAlgoType.mldsa65:
      final apkam = await MlDsa65KeyPair.generate();
      return (
        keys: keys,
        apkamPublicKey: apkam.atPublicKey.publicKey,
        apkamPrivateKey: apkam.atPrivateKey.privateKey,
      );
    case SigningAlgoType.rsa2048:
      final apkam = AtChopsUtil.generateAtPkamKeyPair();
      final publicKey = apkam.atPublicKey.publicKey.toString();
      final privateKey = apkam.atPrivateKey.privateKey.toString();
      // The legacy shape: the flat fields are where every published reader
      // looks, so an rsa2048 activation fills them here and the caller files
      // no typed signing material at all.
      keys
        ..apkamPublicKey = AtBytes.fromString(publicKey)
        ..apkamPrivateKey = AtBytes.fromString(privateKey);
      return (
        keys: keys,
        apkamPublicKey: publicKey,
        apkamPrivateKey: privateKey,
      );
    default:
      throw ArgumentError.value(
          signingAlgo,
          'signingAlgo',
          'onboarding can mint an rsa2048 or an mldsa65 APKAM; '
              '${signingAlgo.name} has no mint path, and defaulting to one of '
              'the others would activate an atSign under an algorithm the '
              'caller did not ask for');
  }
}
