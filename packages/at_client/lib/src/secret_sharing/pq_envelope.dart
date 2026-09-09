/// The two `pqSeal`/`pqOpen` call shapes this package uses, in one place.
///
/// `info` is taken from the caller and never constructed, derived or
/// defaulted — a shared binding would let one substrate's envelope open as
/// another's — and mapping a failure to a substrate's own exception stays at
/// the call site.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart'
    show AtKemAlgorithm, PqOpenException, PqOpenFailure, pqOpen, pqSeal;
import 'package:meta/meta.dart';

/// Seals [plaintext] to [recipientPublicKey] and returns the base64 wire form.
///
/// [info] and [version] have no defaults: a shared `info` would let one
/// substrate's envelope open as another's, and a defaulted version would emit
/// what this build prefers rather than what the recipient agreed to. Throws
/// `PqSealException` if the recipient key is the wrong length or the version
/// is one this build cannot emit.
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
/// Every failure arrives as a `PqOpenException`, a value that is not valid
/// base64 included — on this wire the base64 string *is* the envelope. [info]
/// must be the same value the sender bound, or the AEAD refuses.
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
