import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:meta/meta.dart';

/// [AtPkamSigner] that signs the PKAM challenge with an RSA-2048 private key
/// and SHA-256 — the algorithm atServers verify by default.
///
/// [privateKey] is the PEM-encoded apkam/pkam private key (e.g.
/// `AtKeys.apkamPrivateKey`).
class RsaPkamSigner implements AtPkamSigner {
  final String privateKey;

  RsaPkamSigner(this.privateKey);

  @override
  Uint8List sign(Uint8List challenge) =>
      RsaSigningAlgo(RsaKeyPair.create('', privateKey), HashingAlgoType.sha256)
          .sign(challenge);

  @override
  SigningAlgoType get signingAlgo => SigningAlgoType.rsa2048;

  @override
  HashingAlgoType get hashingAlgo => HashingAlgoType.sha256;
}

/// EXPERIMENTAL — not yet wired into authentication.
///
/// [AtPkamSigner] backed by ML-DSA-65 (post-quantum, FIPS 204). Signing works,
/// but the PKAM *wire* semantics are not finalized: the pkam verb's
/// `hashingAlgo` field has no meaningful value for ML-DSA (hashing is
/// intrinsic), and the RSA-vs-ML-DSA selection policy is undecided. Until that
/// is settled, [hashingAlgo] throws so this signer cannot be wired by accident.
///
/// [secretKey] is the raw 4032-byte ML-DSA-65 secret key (e.g. the
/// `apkam/mldsa65` `privateSigning` material in [AtKeys]).
@experimental
class MlDsaPkamSigner implements AtPkamSigner {
  final Uint8List secretKey;

  MlDsaPkamSigner(this.secretKey);

  @override
  Future<Uint8List> sign(Uint8List challenge) =>
      MlDsa65PureDartAlgo().signBytes(challenge, secretKey: secretKey);

  @override
  SigningAlgoType get signingAlgo => SigningAlgoType.mldsa65;

  @override
  HashingAlgoType get hashingAlgo => throw UnimplementedError(
      'ML-DSA-65 PKAM wire semantics are not finalized; MlDsaPkamSigner is '
      'experimental and not yet wired for authentication');
}
