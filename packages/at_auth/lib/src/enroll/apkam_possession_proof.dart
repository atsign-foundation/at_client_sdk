import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart' show AtEnrollmentException;

/// What an `enroll:update` signs to prove the sender holds the private half of
/// the APKAM public key it is asking the atServer to install: the enrollment
/// id, the key and the algorithm, pipe-separated, signed as UTF-8.
///
/// A cross-tier contract. The atServer assembles the same string from the
/// request it received and verifies the signature against the public key
/// carried in that same request, so the separator, the field order and the
/// spellings are frozen — two repositories have to produce identical bytes and
/// neither compiles against the other.
///
/// [signingAlgo] is the **effective** algorithm: the request's when it carries
/// one, and the enrollment record's otherwise. The atServer interpolates it, so
/// an enrollment whose record names no algorithm, updated by a request that
/// names none either, signs the four literal characters `null` as part of this
/// string. [apkamPossessionSignature] never produces that form, because it
/// requires an algorithm and the caller that supplies it also sends it — but
/// the server accepts it, and a client that omits the field has to know what
/// the record already holds.
String apkamPossessionSignable({
  required String enrollmentId,
  required String apkamPublicKey,
  required String signingAlgo,
}) =>
    '$enrollmentId|$apkamPublicKey|$signingAlgo';

/// Base64 of [apkamPossessionSignable], signed by [apkamPrivateKey] — what an
/// `enroll:update` carries in `EnrollVerbBuilder.apkamPublicKeySignature`.
///
/// [apkamPublicKey] and [apkamPrivateKey] are the two halves of the keypair
/// being installed, spelled as their algorithm spells them: base64 X.509 and
/// base64 PKCS#8 for `rsa2048`, base64 of the raw key material for `mldsa65`.
/// The public half is what the signed string names, and the private half is
/// what signs it, so a mismatched pair produces a signature the atServer
/// verifies against the key it was asked to install and rejects.
///
/// Signed through the at_chops path a PKAM challenge is signed through (pkam
/// mode), because the atServer verifies both through one verifier and the two
/// have to frame a signature identically: a key that can authenticate must be
/// installable, and a key installed here must be able to authenticate
/// afterwards. That path is also where the algorithms diverge — `mldsa65` signs
/// the message bytes directly, while `rsa2048` signs their SHA-256 — so an
/// implementation that hashed for both would fail on the post-quantum path
/// alone, and pass every RSA test written for it.
///
/// pkam mode, never data mode: data mode signs with the **encryption** keypair,
/// and what is proved here is possession of an APKAM authentication key.
///
/// Throws [AtEnrollmentException] for any algorithm other than those two.
/// at_chops' pkam-mode signer selects an RSA implementation for everything that
/// is not `mldsa65`, so an `ecc_secp256r1` key would be signed as though it
/// were RSA; and an ECC APKAM key is held in a secure element, whose private
/// half is never a string a caller could pass here in the first place.
String apkamPossessionSignature({
  required String enrollmentId,
  required String apkamPublicKey,
  required String apkamPrivateKey,
  required SigningAlgoType signingAlgo,
}) {
  if (signingAlgo != SigningAlgoType.rsa2048 &&
      signingAlgo != SigningAlgoType.mldsa65) {
    throw AtEnrollmentException(
        'an enroll:update proves possession of an rsa2048 or mldsa65 APKAM '
        'key; "${signingAlgo.name}" cannot be signed for here');
  }

  final signable = apkamPossessionSignable(
      enrollmentId: enrollmentId,
      apkamPublicKey: apkamPublicKey,
      signingAlgo: signingAlgo.name);

  // The hashing algorithm is stated rather than defaulted: the atServer
  // verifies this signature with SHA-256 and never reads a hashingAlgo off the
  // request, so the two agree only because both name it.
  final signingResult = AtChopsImpl(AtChopsKeys.create(
          null, AtPkamKeyPair.create(apkamPublicKey, apkamPrivateKey)))
      .sign(AtSigningInput(signable)
        ..signingAlgoType = signingAlgo
        ..hashingAlgoType = HashingAlgoType.sha256
        ..signingMode = AtSigningMode.pkam);

  return signingResult.result as String;
}
