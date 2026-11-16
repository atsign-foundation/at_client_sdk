import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/src/auth/at_authenticator.dart' show signPkamChallenge;
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart' show AtBytes, AtSigningException;

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
/// [apkamKeyPair] is an APKAM keypair the caller already holds, used instead
/// of minting one. It is checked with [checkApkamKeyPair] first, so a pair
/// that does not sign under [signingAlgo] is refused with the same error an
/// enrolment gives.
///
/// [mintLegacyMaterial] cuts the RSA encryption keypair, the
/// `selfEncryptionKey` and the `apkamSymmetricKey`. All three travel together
/// deliberately: the symmetric key exists to wrap the other two for conveyance
/// to a later enrollment, so minting it alone would produce a key with nothing
/// to wrap, and minting the pair without it would leave nothing able to convey
/// them. Without the keypair at_client's `AtClient.put` of a public value
/// throws `AtPrivateKeyNotFoundException`, since it signs the value with the
/// RSA encryption private key.
Future<OnboardingMint> mintOnboardingKeys({
  SigningAlgoType signingAlgo = SigningAlgoType.rsa2048,
  bool mintLegacyMaterial = true,
  ({String publicKey, String privateKey})? apkamKeyPair,
}) async {
  final keys = AtKeys();

  if (mintLegacyMaterial) {
    final encryptionKeyPair = RsaKeyPair.generate();
    keys
      ..defaultEncryptionPublicKey = AtBytes.fromString(
        encryptionKeyPair.atPublicKey.publicKey.toString(),
      )
      ..defaultEncryptionPrivateKey = AtBytes.fromString(
        encryptionKeyPair.atPrivateKey.privateKey.toString(),
      )
      ..defaultSelfEncryptionKey = AtBytes.fromString(AESKey.generate(32).key)
      ..apkamSymmetricKey = AtBytes.fromString(AESKey.generate(32).key);
  }

  final apkam = apkamKeyPair == null
      ? await mintApkamKeyPair(signingAlgo)
      : await checkApkamKeyPair(signingAlgo, apkamKeyPair);
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
  SigningAlgoType signingAlgo,
) async {
  switch (signingAlgo) {
    case SigningAlgoType.mldsa65:
      final apkam = await MlDsa65KeyPair.generate();
      return (
        publicKey: apkam.atPublicKey.publicKey,
        privateKey: apkam.atPrivateKey.privateKey,
      );
    case SigningAlgoType.rsa2048:
      final apkam = RsaKeyPair.generate();
      return (
        publicKey: apkam.atPublicKey.publicKey.toString(),
        privateKey: apkam.atPrivateKey.privateKey.toString(),
      );
    default:
      throw _noMintPath(signingAlgo);
  }
}

/// The shape of [mintApkamKeyPair].
typedef ApkamKeyPairMinter =
    Future<({String publicKey, String privateKey})> Function(
      SigningAlgoType signingAlgo,
    );

/// Refuses an APKAM keypair a caller supplied in place of [mintApkamKeyPair]
/// unless it is a working pair under [signingAlgo], and returns it with both
/// halves in standard base64.
///
/// "Working" means the private half signs a fixed string, through
/// [signPkamChallenge] (the signer a `pkam:` uses), and that signature
/// verifies against the public half. A pair that is merely well-formed (halves
/// from two keypairs, all zero bytes, or empty) would be enrolled and then
/// fail every `pkam:` after approval, which `waitForApproval` reads as "not
/// decided yet"; the atServer also refuses to enrol that public key again
/// while the record exists.
///
/// Both halves are canonicalised (`base64Encode(base64Decode(s))`) so a
/// base64url spelling is not sent in one place and re-encoded in the keyfile.
///
/// Throws [AtSigningException] for a pair that is malformed or mismatched and
/// [ArgumentError] for an algorithm with no mint path.
Future<({String publicKey, String privateKey})> checkApkamKeyPair(
  SigningAlgoType signingAlgo,
  ({String publicKey, String privateKey}) apkam,
) async {
  if (signingAlgo != SigningAlgoType.mldsa65 &&
      signingAlgo != SigningAlgoType.rsa2048) {
    throw _noMintPath(signingAlgo);
  }
  Uint8List decodeHalf(String half, String name) {
    try {
      return base64Decode(half);
    } on FormatException catch (e) {
      // Name the half and the position only: a FormatException's own text
      // quotes the characters around the bad one, which for the private half
      // is key material.
      throw AtSigningException(
        'the supplied ${signingAlgo.name} APKAM $name key is not base64'
        '${e.offset == null ? '' : ' (at character ${e.offset})'}',
      );
    }
  }

  final publicBytes = decodeHalf(apkam.publicKey, 'public');
  final canonical = (
    publicKey: base64Encode(publicBytes),
    privateKey: base64Encode(decodeHalf(apkam.privateKey, 'private')),
  );

  if (signingAlgo == SigningAlgoType.mldsa65) {
    MlDsa65KeyPair.create(canonical.publicKey, canonical.privateKey);
  }

  const challenge = 'apkam keypair check';
  final message = Uint8List.fromList(utf8.encode(challenge));
  final bool verified;
  try {
    final signature = base64Decode(
      signPkamChallenge((
        algorithm: signingAlgo,
        publicKey: canonical.publicKey,
        privateKey: canonical.privateKey,
      ), challenge),
    );
    verified = signingAlgo == SigningAlgoType.mldsa65
        ? MlDsa65PureDartAlgo.verifyBytesSync(
            message,
            signature: signature,
            publicKey: publicBytes,
          )
        : await RsaSignatureAlgo.rsa2048().verifyBytes(
            message,
            signature: signature,
            publicKey: publicBytes,
          );
  } on AtSigningException {
    rethrow;
  } catch (e) {
    throw AtSigningException(
      'the supplied ${signingAlgo.name} APKAM keypair cannot sign (${e.runtimeType})',
    );
  }
  if (!verified) {
    throw AtSigningException(
      'the supplied ${signingAlgo.name} APKAM private key does not match '
      'its public key',
    );
  }
  return canonical;
}

ArgumentError _noMintPath(SigningAlgoType signingAlgo) => ArgumentError.value(
  signingAlgo,
  'signingAlgo',
  'an APKAM authentication keypair can be minted as rsa2048 or '
      'mldsa65; ${signingAlgo.name} has no mint path, and defaulting '
      'to one of the others would enrol under an algorithm the caller '
      'did not ask for',
);
