/// The two `pqSeal`/`pqOpen` call shapes this package uses, in one place.
///
/// Both substrates that seal — the pairwise envelope and the `at/nskey`
/// conveyance — carry their payload as base64 on the wire and have to turn a
/// failure into their own contract's answer. What they must NOT share is the
/// `info` they bind: `at_client/secret_sharing/v1` against
/// `at/nskey/…:<owner>:<namespace>`. That separation is what stops an envelope
/// from one substrate being opened as the other's, so these functions take
/// `info` from the caller and never construct, derive or default one. There is
/// nothing here for two substrates to converge onto.
///
/// The mapping from a failure to a substrate's own exception stays at the call
/// site, because it genuinely differs: the pairwise sweep skips the envelope
/// and moves on, while the nskey provider owes its caller an
/// `AtDecryptionException`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart'
    show AtKemAlgorithm, PqOpenException, PqOpenFailure, pqOpen, pqSeal;
import 'package:meta/meta.dart';

/// Seals [plaintext] to [recipientPublicKey] and returns the base64 wire form.
///
/// [info] and [version] are both required and neither has a default. `info`
/// because a shared binding is the one bug a shared seal path could introduce,
/// and a default is how it would arrive — by a call site saying nothing rather
/// than by anyone choosing it. `version` because at_chops defaults it to
/// `pqSealDefaultVersion` while both callers here negotiate it from what the
/// recipient says it can open; a default would let a new call site quietly
/// emit whatever this build happens to prefer to a peer that had agreed on
/// something else. The versions differ by KEM, so that is not a downgrade but
/// an unopenable record.
///
/// Throws `PqSealException` if the recipient key is the wrong length or the
/// version is one this build cannot emit.
@internal
Future<String> pqSealToBase64(
  AtKemAlgorithm kem,
  Uint8List recipientPublicKey,
  Uint8List plaintext, {
  required Uint8List info,
  required int version,
}) async {
  final Uint8List sealed = await pqSeal(
    kem,
    recipientPublicKey,
    plaintext,
    info: info,
    version: version,
  );
  return base64Encode(sealed);
}

/// Opens a base64 wire value produced by [pqSealToBase64].
///
/// Every failure arrives as a `PqOpenException`, including a value that is not
/// valid base64. The decode is inside the guarded region deliberately: on this
/// wire the base64 string *is* the envelope, so a string that will not decode
/// is a malformed envelope and belongs with the other malformed ones. Left
/// outside, it reaches callers as a `FormatException` — a type none of them
/// names — and gets classified as something transient when it is permanent.
///
/// [info] is required for the reason given on [pqSealToBase64], and must be
/// the same value the sender bound or the AEAD refuses.
@internal
Future<Uint8List> pqOpenFromBase64(
  AtKemAlgorithm kem,
  Uint8List recipientSecretKey,
  String wireBase64, {
  required Uint8List info,
}) async {
  final Uint8List envelope;
  try {
    envelope = base64Decode(wireBase64);
  } on FormatException catch (e) {
    throw PqOpenException(
        PqOpenFailure.malformedEnvelope, 'wire value is not valid base64: $e');
  }
  return pqOpen(kem, recipientSecretKey, envelope, info: info);
}
