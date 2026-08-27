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

  final apkam = await mintApkamKeyPair(signingAlgo);
  if (signingAlgo == SigningAlgoType.rsa2048) {
    // The legacy shape: the flat fields are where every published reader
    // looks, so an rsa2048 activation fills them here and the caller files
    // no typed signing material at all.
    keys
      ..apkamPublicKey = AtBytes.fromString(apkam.publicKey)
      ..apkamPrivateKey = AtBytes.fromString(apkam.privateKey);
  }
  return (
    keys: keys,
    apkamPublicKey: apkam.publicKey,
    apkamPrivateKey: apkam.privateKey,
  );
}

/// Mints an APKAM **authentication** keypair under [signingAlgo], base64 of
/// the raw key in both halves.
///
/// Shared by onboarding and by app enrolment so the two cannot drift: an
/// algorithm one of them can mint and the other cannot is a state where the
/// same posture produces different key material depending on which door an
/// atSign came through.
///
/// Files nothing and decides nothing about where the halves are stored. That
/// is the caller's, because it differs: rsa2048 belongs in the flat fields
/// every published reader looks at, and anything else belongs in typed
/// material under an enrollment id — which for an app enrolment is not known
/// until the atServer answers.
Future<({String publicKey, String privateKey})> mintApkamKeyPair(
    SigningAlgoType signingAlgo) async {
  switch (signingAlgo) {
    case SigningAlgoType.mldsa65:
      final apkam = await MlDsa65KeyPair.generate();
      return (
        publicKey: apkam.atPublicKey.publicKey,
        privateKey: apkam.atPrivateKey.privateKey,
      );
    case SigningAlgoType.rsa2048:
      final apkam = AtChopsUtil.generateAtPkamKeyPair();
      return (
        publicKey: apkam.atPublicKey.publicKey.toString(),
        privateKey: apkam.atPrivateKey.privateKey.toString(),
      );
    default:
      throw ArgumentError.value(
          signingAlgo,
          'signingAlgo',
          'an APKAM authentication keypair can be minted as rsa2048 or '
              'mldsa65; ${signingAlgo.name} has no mint path, and defaulting '
              'to one of the others would enrol under an algorithm the caller '
              'did not ask for');
  }
}
