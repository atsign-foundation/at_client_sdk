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
    show
        AtKemAlgorithm,
        PqOpenException,
        PqOpenFailure,
        PqSealException,
        pqOpen,
        pqSeal;
import 'package:meta/meta.dart';

/// Seals [plaintext] to [recipientPublicKey] and returns the base64 wire form.
///
/// [info] and [version] have no defaults: a shared `info` would let one
/// substrate's envelope open as another's, and a defaulted version would emit
/// what this build prefers rather than what the recipient agreed to. Every
/// failure arrives as a `PqSealException`: a recipient key of the wrong length
/// or one the KEM cannot use, and a version this build cannot emit.
@internal
Future<String> pqSealToBase64(
  AtKemAlgorithm kem,
  Uint8List recipientPublicKey,
  Uint8List plaintext, {
  required Uint8List info,
  required int version,
}) async {
  final Uint8List sealed;
  try {
    sealed = await pqSeal(
      kem,
      recipientPublicKey,
      plaintext,
      info: info,
      version: version,
    );
  } on StateError catch (e) {
    throw PqSealException('the KEM could not seal to the recipient key: $e');
  }
  return base64Encode(sealed);
}

/// Opens a base64 wire value produced by [pqSealToBase64].
///
/// Every failure arrives as a `PqOpenException`: a value that is not valid
/// base64 included, since on this wire the base64 string *is* the envelope,
/// and a `StateError` from the KEM, as `PqOpenFailure.authFailure`. [info]
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
  try {
    return await pqOpen(kem, recipientSecretKey, envelope, info: info);
  } on StateError catch (e) {
    throw PqOpenException(
        PqOpenFailure.authFailure, 'the KEM refused the envelope: $e');
  }
}
