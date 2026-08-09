/// [pqSeal]/[pqOpen]: public-key encryption to a KEM-held key, in a versioned
/// envelope `ver || ctLen || kemCt || aeadCiphertext || tag`.
///
/// The envelope framing is Atsign-Protocol-internal at every version; what
/// `ver` selects is the construction inside it (one table row each, see
/// `_versions`):
///   - `0x01`, the default: HPKE-*style* — X-Wing with the custom
///     `atPQv1-base` key schedule (HKDF-SHA256) and AES-256-GCM. Not RFC
///     9180; do not expect interop with off-the-shelf HPKE implementations.
///   - `0x02` and `0x03`: genuine RFC 9180 Base-mode key schedules (§5.1
///     verbatim, in `rfc9180_hpke.dart`), checked against the IETF HPKE
///     working group's published vectors.
///
/// The KEM's 32-byte shared secret is already uniformly random, so the KDF
/// step provides context binding ([info]) and AEAD key/nonce derivation —
/// not randomness extraction.
///
/// Byte-level specification: `docs/projects/pq/seal-spec.md`, with
/// cross-implementation vectors in `test/vectors/pq_seal_v1.json`.
library;

import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../hashing/hkdf.dart';
import 'at_aead.dart';
import 'rfc9180_hpke.dart';

/// The version [pqSeal] emits when the caller does not choose one.
///
/// Raising this is a **fleet-wide** decision, not a local one: every reader has
/// to understand the new version before any writer emits it, and a sealer has
/// no way to discover what its recipients can open. Prefer passing
/// `pqSeal(version:)` from a caller that knows — the key package's advertised
/// suites, say — over changing the default.
const int pqSealDefaultVersion = 0x01;

/// All versions [pqOpen] can decrypt, and therefore all [pqSeal] will emit.
///
/// Add new versions here alongside their row in [_versions]; do not remove
/// old ones until every peer has upgraded past them, because a removed
/// version turns records already written into permanent
/// [PqOpenFailure.versionMismatch] failures.
const Set<int> pqSealSupportedVersions = {0x01, 0x02, 0x03};

/// What one wire version means: how the AEAD key and nonce are derived, and
/// which AEAD seals the body.
///
/// A row carries either [suite] (an RFC 9180 ciphersuite, whose §5.1 schedule
/// derives and whose `suite_id`-inside-every-label is the version's domain
/// separation) or [suiteLabel] (the custom raw-concatenation schedule, whose
/// distinct label is what keeps that version's HKDF-derived keys
/// domain-separated from every other version's).
final class _SealVersion {
  /// The RFC 9180 ciphersuite this version derives and seals with; null for
  /// the custom-schedule version.
  final HpkeSuite? suite;

  /// The custom schedule's domain-separation label; null for RFC 9180
  /// versions, which must never be given one — relabelling an envelope across
  /// versions has to keep failing in both directions.
  final String? suiteLabel;

  final AtAeadAlgorithm _customAead;

  const _SealVersion.rfc9180(HpkeSuite this.suite)
      : suiteLabel = null,
        // Unused on this arm: the suite names its own AEAD.
        _customAead = const AesGcm256Aead();

  const _SealVersion.custom(
      {required String this.suiteLabel, required AtAeadAlgorithm aead})
      : suite = null,
        _customAead = aead;

  /// The suite's AEAD where there is a suite, so the cipher cannot diverge
  /// from the `suite_id` the vectors pin; the row's own otherwise.
  AtAeadAlgorithm get aead => suite?.aead ?? _customAead;
}

/// The version table — one row per wire version, keyed by the `ver` byte.
///
/// A version byte rather than a suite field on the wire because the KEM is
/// already fixed by the recipient's advertised key: nothing can seal
/// ML-KEM-1024 to a hybrid encapsulation key or the reverse. The version byte
/// therefore names the whole suite, and an opener needs no other input.
/// [pqSealSupportedVersions] is the public face of this table's key set; a
/// unit test pins them equal.
const Map<int, _SealVersion> _versions = {
  // HPKE-style over X-Wing: the custom `atPQv1-base` schedule. `0x01` is
  // X-Wing's alone — there is no ML-KEM `atPQv1-base` envelope and there
  // never was one.
  0x01: _SealVersion.custom(suiteLabel: 'atPQv1-base', aead: AesGcm256Aead()),
  // RFC 9180 at the hybrid suite — ChaCha20-Poly1305 because it is the only
  // AEAD the HPKE working group publishes `0x647A` vectors for.
  0x02: _SealVersion.rfc9180(HpkeSuite.xWingHkdfSha256ChaCha20Poly1305),
  // RFC 9180 at pure ML-KEM-1024 — the no-hybrid option, and the only
  // published HPKE suite for KEM `0x0042` at a 256-bit AEAD.
  0x03: _SealVersion.rfc9180(HpkeSuite.mlKem1024HkdfSha384Aes256Gcm),
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
/// [kem] is the KEM instance to use (e.g. `XWingFfiAlgo` or
/// `XWingPureDartAlgo`). [info] binds the key schedule to a usage context;
/// [aad] is authenticated-but-not-encrypted associated data. Both must be
/// supplied identically to [pqOpen] or opening fails.
///
/// [version] selects the construction to emit, and must be one of
/// [pqSealSupportedVersions]. It exists so a sealer that knows what its
/// recipient can open — from the suites its key package advertises — can choose
/// per call. Without it, introducing a new construction would mean flipping a
/// global constant and breaking every reader that had not upgraded yet, since
/// there would be no way to emit the old version to old peers and the new one
/// to new peers at the same time.
///
/// Returns the serialized wire envelope (raw bytes).
Future<Uint8List> pqSeal(
  AtKemAlgorithm kem,
  Uint8List recipientPublicKey,
  Uint8List plaintext, {
  Uint8List? info,
  Uint8List? aad,
  int version = pqSealDefaultVersion,
}) async {
  final _SealVersion? row = _versions[version];
  if (row == null) {
    // Refused rather than emitted: an envelope this build cannot open is one
    // nobody can, since it would carry a suite label that exists nowhere.
    throw PqSealException(
        'cannot seal at version 0x${version.toRadixString(16)} — this build '
        'supports ${pqSealSupportedVersions.map((v) => '0x${v.toRadixString(16)}').join(', ')}');
  }

  final enc = await kem.encapsulate(recipientPublicKey);
  final _DerivedKey dk = _deriveKeyAndNonce(enc.sharedSecret, version, info);

  // body = ciphertext || tag in every version.
  final Uint8List body = await row.aead.encrypt(plaintext,
      key: dk.key, nonce: dk.nonce, aad: aad ?? const <int>[]);

  // envelope: ver(1) || ctLen(2,BE) || kemCt || aeadCiphertext || tag
  final out = BytesBuilder(copy: false);
  out.addByte(version);
  out.addByte((enc.ciphertext.length >> 8) & 0xff);
  out.addByte(enc.ciphertext.length & 0xff);
  out.add(enc.ciphertext);
  out.add(body);
  return out.toBytes();
}

/// Open an envelope produced by [pqSeal] using [recipientSecretKey].
///
/// [kem] must be the same KEM type used by the sender. [info]/[aad] must
/// match what the sender supplied.
///
/// Throws [PqOpenException] on any failure (see [PqOpenFailure]).
Future<Uint8List> pqOpen(
  AtKemAlgorithm kem,
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
  final _SealVersion? row = _versions[ver];
  if (row == null) {
    throw PqOpenException(PqOpenFailure.versionMismatch,
        'unsupported envelope version 0x${ver.toRadixString(16)}');
  }
  final int ctLen = (envelope[1] << 8) | envelope[2];
  if (envelope.length < 3 + ctLen + row.aead.tagLength) {
    throw PqOpenException(PqOpenFailure.malformedEnvelope,
        'declared ciphertext length overruns envelope');
  }
  final Uint8List kemCt = Uint8List.sublistView(envelope, 3, 3 + ctLen);
  // aeadBody = aeadCiphertext || tag; the AEAD splits the tag off itself.
  final Uint8List aeadBody = Uint8List.sublistView(envelope, 3 + ctLen);

  // Decapsulation rejects a wrong-length secret key or KEM ciphertext with an
  // ArgumentError. That is still a malformed envelope from the caller's side,
  // and letting it escape would break the documented contract that every
  // failure arrives as a PqOpenException — leaving a caller who catches the
  // documented type with an uncaught error on a bad input.
  final Uint8List ss;
  try {
    ss = await kem.decapsulate(recipientSecretKey, kemCt);
  } on ArgumentError catch (e) {
    throw PqOpenException(PqOpenFailure.malformedEnvelope,
        'decapsulation rejected the input: $e');
  }
  final _DerivedKey dk = _deriveKeyAndNonce(ss, ver, info);

  try {
    return await row.aead.decrypt(aeadBody,
        key: dk.key, nonce: dk.nonce, aad: aad ?? const <int>[]);
  } on AtDecryptionException {
    throw PqOpenException(
        PqOpenFailure.authFailure, 'AEAD authentication failed');
  }
}

/// The AEAD key and nonce [pqSeal] derives from a KEM shared secret — the
/// `atPQv1-base` key schedule, exposed so a conformance suite can check it
/// directly.
///
/// A second implementation that disagrees here produces envelopes this one
/// cannot open, and the failure arrives as an AEAD authentication error that
/// says nothing about which side is wrong. Comparing the schedule's own output
/// turns that into a one-line diff.
///
/// [version] selects the suite label, so a caller can check a version this
/// build still reads but no longer emits. See
/// `docs/projects/pq/seal-spec.md` and `test/vectors/pq_seal_v1.json`.
@visibleForTesting
({Uint8List key, Uint8List nonce}) pqSealDeriveKeyAndNonce(
  Uint8List sharedSecret, {
  Uint8List? info,
  int version = pqSealDefaultVersion,
}) {
  final dk = _deriveKeyAndNonce(sharedSecret, version, info);
  return (key: dk.key, nonce: dk.nonce);
}

// ── internals ───────────────────────────────────────────────────────────────

class _DerivedKey {
  final Uint8List key;
  final Uint8List nonce;
  _DerivedKey(this.key, this.nonce);
}

/// Derives the AEAD key and nonce from the KEM [ss] per [version]'s table
/// row: RFC 9180's schedule where the row has a suite, else the custom
/// schedule bound to the row's label and the caller's [info] (two HKDF labels,
/// `0x01`/`0x02`, keep key and nonce independent).
_DerivedKey _deriveKeyAndNonce(Uint8List ss, int version, Uint8List? info) {
  final _SealVersion? row = _versions[version];
  if (row == null) {
    throw ArgumentError(
        'no key schedule for version 0x${version.toRadixString(16)} — this '
        'build knows ${pqSealSupportedVersions.map((v) => '0x${v.toRadixString(16)}').join(', ')}');
  }
  final HpkeSuite? suite = row.suite;
  if (suite != null) {
    // RFC 9180 Base mode, verbatim. Both suites are checked against the IETF
    // HPKE working group's published vectors in test/rfc9180_hpke_test.dart —
    // bytes nobody here produced, which is the difference between these
    // versions and 0x01.
    final ks = hpkeKeyScheduleBase(suite, ss, info: info);
    return _DerivedKey(ks.key, ks.baseNonce);
  }
  final Uint8List suiteInfo = _concat([
    Uint8List.fromList(row.suiteLabel!.codeUnits),
    info ?? Uint8List(0),
  ]);
  final Uint8List key = HkdfSha256.deriveKey(ss,
      info: _concat([suiteInfo, _u8(0x01)]), length: 32);
  final Uint8List nonce = HkdfSha256.deriveKey(ss,
      info: _concat([suiteInfo, _u8(0x02)]), length: row.aead.nonceLength);
  return _DerivedKey(key, nonce);
}

Uint8List _u8(int b) => Uint8List.fromList([b]);

Uint8List _concat(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}
