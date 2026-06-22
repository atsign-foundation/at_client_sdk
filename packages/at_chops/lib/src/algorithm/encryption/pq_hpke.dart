import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_chops/src/algorithm/at_iv.dart';
import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:at_commons/at_commons.dart';

import '../hashing/hkdf.dart';
import 'aes_gcm.dart';

/// HPKE-*style* authenticated public-key encryption over an X-Wing KEM.
///
/// Reuses the RFC 9180 HPKE construction shape:
///   - KEM      = caller-supplied [AtKemAlgorithm] (intended: X-Wing)
///   - KDF      = HKDF-SHA256 ([HkdfSha256])
///   - AEAD     = AES-256-GCM ([AesGcm256EncryptionAlgo])
///
/// NOT wire-compatible with RFC 9180 HPKE. This uses a custom, internal
/// envelope (`ver || ctLen || kemCt || ct || tag`) and a custom key schedule,
/// so do NOT expect interop with off-the-shelf HPKE implementations — it is an
/// at_protocol-internal envelope only.
///
/// The KEM's 32-byte shared secret is already uniformly random, so the HKDF
/// step provides context binding ([info]) and AEAD key/nonce derivation —
/// not randomness extraction.

/// Version emitted by [pqSeal]. Bump this when introducing a new construction.
const int _envelopeVersion = 0x01;

/// All versions [pqOpen] can decrypt. Add new versions here alongside their
/// suite label in [_suiteLabelFor]; do not remove old ones until all peers
/// have upgraded past them.
const Set<int> _supportedVersions = {0x01};

const int _gcmNonceLen = AesGcm256EncryptionAlgo.nonceLength;
const int _gcmTagLen = AesGcm256EncryptionAlgo.tagLength;

/// Returns the suite label for [version]. Each version must have a distinct
/// label so its HKDF-derived keys are domain-separated from every other version.
Uint8List _suiteLabelFor(int version) => switch (version) {
      0x01 => Uint8List.fromList('atPQv1-base'.codeUnits),
      _ => throw ArgumentError(
          'no suite label for version 0x${version.toRadixString(16)}'),
    };

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

/// Seal [plaintext] so only the holder of the secret key paired with
/// [recipientPublicKey] can open it.
///
/// [xwing] is the KEM instance to use (e.g. `XWingFfiAlgo` or
/// `XWingPureDartAlgo`). [info] binds the key schedule to a usage context;
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
  final _DerivedKey dk =
      _deriveKeyAndNonce(enc.sharedSecret, _envelopeVersion, info);

  // body = gcmCipherText || tag(16), per AesGcm256EncryptionAlgo's wire format.
  final Uint8List body = await AesGcm256EncryptionAlgo(_aesKey(dk.key)).encrypt(
    plaintext,
    iv: InitialisationVector(dk.nonce),
    aad: aad ?? const <int>[],
  );

  // envelope: ver(1) || ctLen(2,BE) || kemCt || gcmCipherText || tag(16)
  final out = BytesBuilder(copy: false);
  out.addByte(_envelopeVersion);
  out.addByte((enc.ciphertext.length >> 8) & 0xff);
  out.addByte(enc.ciphertext.length & 0xff);
  out.add(enc.ciphertext);
  out.add(body);
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
  final int ver = envelope[0];
  if (!_supportedVersions.contains(ver)) {
    throw PqOpenException(PqOpenFailure.versionMismatch,
        'unsupported envelope version 0x${ver.toRadixString(16)}');
  }
  final int ctLen = (envelope[1] << 8) | envelope[2];
  if (envelope.length < 3 + ctLen + _gcmTagLen) {
    throw PqOpenException(PqOpenFailure.malformedEnvelope,
        'declared ciphertext length overruns envelope');
  }
  final Uint8List kemCt = Uint8List.sublistView(envelope, 3, 3 + ctLen);
  // gcmBody = gcmCipherText || tag(16); AesGcm256EncryptionAlgo splits the tag.
  final Uint8List gcmBody = Uint8List.sublistView(envelope, 3 + ctLen);

  final Uint8List ss = await xwing.decapsulate(recipientSecretKey, kemCt);
  final _DerivedKey dk = _deriveKeyAndNonce(ss, ver, info);

  try {
    return await AesGcm256EncryptionAlgo(_aesKey(dk.key)).decrypt(
      gcmBody,
      iv: InitialisationVector(dk.nonce),
      aad: aad ?? const <int>[],
    );
  } on AtDecryptionException {
    throw PqOpenException(
        PqOpenFailure.authFailure, 'AEAD authentication failed');
  }
}

// ── internals ───────────────────────────────────────────────────────────────

class _DerivedKey {
  final Uint8List key;
  final Uint8List nonce;
  _DerivedKey(this.key, this.nonce);
}

/// Derives the AEAD key and nonce from the KEM [ss], bound to the suite label
/// for [version] and the caller's [info]. Two HKDF labels (`0x01`/`0x02`) keep
/// key and nonce independent.
_DerivedKey _deriveKeyAndNonce(Uint8List ss, int version, Uint8List? info) {
  final Uint8List suiteInfo =
      _concat([_suiteLabelFor(version), info ?? Uint8List(0)]);
  final Uint8List key = HkdfSha256.deriveKey(ss,
      info: _concat([suiteInfo, _u8(0x01)]), length: 32);
  final Uint8List nonce = HkdfSha256.deriveKey(ss,
      info: _concat([suiteInfo, _u8(0x02)]), length: _gcmNonceLen);
  return _DerivedKey(key, nonce);
}

/// Wraps a raw 32-byte key as an [AESKey] (which carries it base64-encoded,
/// per the at_chops contract).
AESKey _aesKey(Uint8List rawKey) => AESKey(base64Encode(rawKey));

Uint8List _u8(int b) => Uint8List.fromList([b]);

Uint8List _concat(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}
