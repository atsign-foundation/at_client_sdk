import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:cryptography/cryptography.dart';

/// HPKE-base-style authenticated public-key encryption over an X-Wing KEM.
///
/// Mirrors RFC 9180 HPKE SealBase/OpenBase with:
///   - KEM      = caller-supplied [AtKemAlgorithm] (intended: X-Wing)
///   - KDF      = HKDF-SHA256
///   - AEAD     = AES-256-GCM
///
/// The KEM's 32-byte shared secret is already uniformly random, so the HKDF
/// step provides HPKE-style context binding ([info]) and AEAD key/nonce
/// derivation — not randomness extraction.

/// Envelope format version. `v1` = single-shot seal with a derived nonce.
const int _envelopeVersion = 0x01;

const int _gcmNonceLen = 12;
const int _gcmTagLen = 16;

final Uint8List _suiteLabel = Uint8List.fromList('atPQv1-base'.codeUnits);
final Uint8List _polConfirmLabel =
    Uint8List.fromList('atPQv1-polconfirm'.codeUnits);
final Uint8List _sessionLabel =
    Uint8List.fromList('atPQv1-session'.codeUnits);

final AesGcm _aesGcm = AesGcm.with256bits();

/// Why a [pqOpen] call failed.
///
/// All AEAD-level failures (wrong key, tampered ciphertext, mismatched
/// [info]/[aad]) collapse to [authFailure] by design — X-Wing is an
/// implicit-rejection KEM, so there is no distinct "wrong key" oracle.
enum PqOpenFailure { versionMismatch, malformedEnvelope, authFailure }

/// Thrown by [pqSeal] on caller misuse (e.g. a wrong-length public key).
class PqSealException implements Exception {
  final String message;
  PqSealException(this.message);
  @override
  String toString() => 'PqSealException: $message';
}

/// Thrown by [pqOpen] for any failure. Inspect [reason].
class PqOpenException implements Exception {
  final PqOpenFailure reason;
  final String message;
  PqOpenException(this.reason, this.message);
  @override
  String toString() => 'PqOpenException($reason): $message';
}

/// Seal [plaintext] to the holder of [recipientPublicKey].
///
/// [xwing] is the KEM instance to use (e.g. [XWingFfiAlgo] or
/// [XWingPureDartAlgo]). [info] binds the key schedule to a usage context;
/// [aad] is authenticated-but-not-encrypted associated data. Both must be
/// supplied identically to [pqOpen] or opening fails.
///
/// Returns the serialized wire envelope (raw bytes).
Future<Uint8List> pqSeal(
  AtKemAlgorithm xwing,
  Uint8List recipientPublicKey,
  Uint8List plaintext, {
  Uint8List? info,
  Uint8List? aad,
}) async {
  final enc = await xwing.encapsulate(recipientPublicKey);
  final _DerivedKey dk = await _deriveKeyAndNonce(enc.sharedSecret, info);

  final SecretBox box = await _aesGcm.encrypt(
    plaintext,
    secretKey: SecretKey(dk.key),
    nonce: dk.nonce,
    aad: aad ?? const <int>[],
  );

  // envelope: ver(1) || ctLen(2,BE) || kemCt || gcmCipherText || tag(16)
  final out = BytesBuilder(copy: false);
  out.addByte(_envelopeVersion);
  out.addByte((enc.ciphertext.length >> 8) & 0xff);
  out.addByte(enc.ciphertext.length & 0xff);
  out.add(enc.ciphertext);
  out.add(box.cipherText);
  out.add(box.mac.bytes);
  return out.toBytes();
}

/// Open an envelope produced by [pqSeal] using [recipientSecretKey].
///
/// [xwing] must be the same KEM type used by the sender. [info]/[aad] must
/// match what the sender supplied.
///
/// Throws [PqOpenException] on any failure (see [PqOpenFailure]).
Future<Uint8List> pqOpen(
  AtKemAlgorithm xwing,
  Uint8List recipientSecretKey,
  Uint8List envelope, {
  Uint8List? info,
  Uint8List? aad,
}) async {
  if (envelope.length < 3) {
    throw PqOpenException(
        PqOpenFailure.malformedEnvelope, 'envelope shorter than header');
  }
  if (envelope[0] != _envelopeVersion) {
    throw PqOpenException(PqOpenFailure.versionMismatch,
        'unsupported envelope version 0x${envelope[0].toRadixString(16)}');
  }
  final int ctLen = (envelope[1] << 8) | envelope[2];
  if (envelope.length < 3 + ctLen + _gcmTagLen) {
    throw PqOpenException(PqOpenFailure.malformedEnvelope,
        'declared ciphertext length overruns envelope');
  }
  final Uint8List kemCt = Uint8List.sublistView(envelope, 3, 3 + ctLen);
  final Uint8List gcmBody = Uint8List.sublistView(envelope, 3 + ctLen);
  final Uint8List cipherText =
      Uint8List.sublistView(gcmBody, 0, gcmBody.length - _gcmTagLen);
  final Uint8List tag =
      Uint8List.sublistView(gcmBody, gcmBody.length - _gcmTagLen);

  final Uint8List ss = await xwing.decapsulate(recipientSecretKey, kemCt);
  final _DerivedKey dk = await _deriveKeyAndNonce(ss, info);

  try {
    final List<int> clear = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: dk.nonce, mac: Mac(tag)),
      secretKey: SecretKey(dk.key),
      aad: aad ?? const <int>[],
    );
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw PqOpenException(
        PqOpenFailure.authFailure, 'AEAD authentication failed');
  }
}

/// Derive a 32-byte key-confirmation tag from [sharedSecret].
///
/// Used by the inter-server from/pol handshake so the raw shared secret never
/// traverses the wire. [info] should bind the tag to its context (e.g.
/// sessionID || fromAtSign).
Future<Uint8List> pqDeriveConfirmationTag(
    Uint8List sharedSecret, Uint8List info) {
  return _hkdf(sharedSecret, _concat([_polConfirmLabel, info]), 32);
}

/// Derive a 32-byte session key from [sharedSecret].
///
/// Called on both sides after a successful from/pol PQ handshake. [info]
/// should bind the key to its context (e.g. sessionID || fromAtSign). Uses
/// a distinct HKDF label so the session key is independent from the
/// confirmation tag.
Future<Uint8List> pqDeriveSessionKey(
    Uint8List sharedSecret, Uint8List info) {
  return _hkdf(sharedSecret, _concat([_sessionLabel, info]), 32);
}

// ── internals ───────────────────────────────────────────────────────────────

class _DerivedKey {
  final Uint8List key;
  final Uint8List nonce;
  _DerivedKey(this.key, this.nonce);
}

Future<_DerivedKey> _deriveKeyAndNonce(Uint8List ss, Uint8List? info) async {
  final Uint8List suiteInfo = _concat([_suiteLabel, info ?? Uint8List(0)]);
  final Uint8List key = await _hkdf(ss, _concat([suiteInfo, _u8(0x01)]), 32);
  final Uint8List nonce =
      await _hkdf(ss, _concat([suiteInfo, _u8(0x02)]), _gcmNonceLen);
  return _DerivedKey(key, nonce);
}

Future<Uint8List> _hkdf(Uint8List ikm, Uint8List info, int length) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: length);
  final SecretKey derived = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: const <int>[],
    info: info,
  );
  return Uint8List.fromList(await derived.extractBytes());
}

Uint8List _u8(int b) => Uint8List.fromList([b]);

Uint8List _concat(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}
