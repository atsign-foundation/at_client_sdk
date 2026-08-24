/// [pqSeal]/[pqOpen]: public-key encryption to a KEM-held key, in a versioned
/// envelope `ver || ctLen || kemCt || aeadCiphertext || tag`.
///
/// The envelope framing is Atsign-Protocol-internal at every version; what
/// `ver` selects is the construction inside it (one table row each, see
/// `_versions`):
///   - `0x02` and `0x03`: RFC 9180 Base-mode key schedules (§5.1 verbatim,
///     in `rfc9180_hpke.dart`), checked against the IETF HPKE working group's
///     published vectors. They differ in their KEM, which is why they are
///     separate versions rather than one version carrying a suite field.
///
/// The KEM's 32-byte shared secret is already uniformly random, so the KDF
/// step provides context binding ([info]) and AEAD key/nonce derivation —
/// not randomness extraction.
///
/// Every version is attested by the working group's own vectors
/// (`test/vectors/hpke_wg_0x647a_chacha.json`,
/// `test/vectors/hpke_wg_0x0042_mlkem1024.json`) rather than by any this
/// project generated for itself.
library;

import 'dart:typed_data';

import 'package:at_chops/src/algorithm/at_algorithm.dart';
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import 'at_aead.dart';
import 'rfc9180_hpke.dart';

/// The version [pqSeal] emits when the caller does not choose one.
///
/// Raising this is a **fleet-wide** decision, not a local one: every reader has
/// to understand the new version before any writer emits it, and a sealer has
/// no way to discover what its recipients can open. Prefer passing
/// `pqSeal(version:)` from a caller that knows — the key package's advertised
/// suites, say — over changing the default.
const int pqSealDefaultVersion = 0x02;

/// All versions [pqOpen] can decrypt, and therefore all [pqSeal] will emit.
///
/// Add new versions here alongside their row in [_versions]; do not remove
/// old ones until every peer has upgraded past them, because a removed
/// version turns records already written into permanent
/// [PqOpenFailure.versionMismatch] failures.
///
/// `0x01` — X-Wing under the bespoke `atPQv1-base` schedule — was removed
/// under that rule rather than in spite of it. The subsystem that writes
/// durable sealed records does not exist in any published build, so no peer
/// held one to upgrade past; the published envelopes that could carry it are
/// the pairwise ones, and those expire on a 7-day ttl.
const Set<int> pqSealSupportedVersions = {0x02, 0x03};

/// What one wire version means: how the AEAD key and nonce are derived, and
/// which AEAD seals the body.
///
/// Every row is an RFC 9180 ciphersuite, whose §5.1 schedule derives and whose
/// `suite_id`-inside-every-label is the version's domain separation. A row
/// could once carry a bespoke label naming a raw-concatenation schedule
/// instead; `0x01` was the only version that did, and with it gone the suite
/// is the whole of what a row is.
final class _SealVersion {
  /// The RFC 9180 ciphersuite this version derives and seals with.
  final HpkeSuite suite;

  const _SealVersion.rfc9180(this.suite);

  /// Always the suite's own AEAD, so the cipher cannot diverge from the
  /// `suite_id` the working group's vectors pin.
  AtAeadAlgorithm get aead => suite.aead;
}

/// The version table — one row per wire version, keyed by the `ver` byte.
///
/// A version byte rather than a suite field on the wire because the KEM is
/// already fixed by the recipient's advertised key: nothing can seal
/// ML-KEM-1024 to a hybrid encapsulation key or the reverse. The version byte
/// therefore names the whole suite, and an opener needs no other input.
///
/// [pqSeal] enforces that rather than assuming it. `kem` and `version` are
/// independent arguments, so a caller can pair a KEM with a version that names
/// a different one — and because [pqSealDefaultVersion] supplies a version to
/// callers that name none, the mismatch is reachable without anyone choosing
/// it. Such an envelope round-trips against a peer making the same mistake and
/// is unopenable by anyone following the rule above, which is why the seal
/// refuses it outright. The check compares the encapsulation length against
/// the suite's [HpkeSuite.nEnc].
///
/// [pqSealSupportedVersions] is the public face of this table's key set; a
/// unit test pins them equal.
const Map<int, _SealVersion> _versions = {
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
/// [info] is **required**, and deliberately has no default. It used to be
/// optional, and omitting it derived the same key schedule as passing an empty
/// one — so two protocols that both forgot it shared a binding, and each could
/// open the other's envelopes. That is the failure this parameter exists to
/// prevent, and a default is what made it reachable by saying nothing. A caller
/// that genuinely wants no binding passes `Uint8List(0)` and says so.
/// Contrast [version], which keeps its default: a version mismatch surfaces as
/// a named [PqOpenFailure.versionMismatch], while an `info` mismatch is
/// indistinguishable from a tampered envelope — and a *shared* wrong `info`
/// raises no error at all.
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
  required Uint8List info,
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

  // Encapsulation rejects a wrong-length public key with an ArgumentError.
  // Mapped here for the same reason pqOpen maps decapsulate's: the documented
  // contract is that caller misuse arrives as PqSealException, and a raw
  // ArgumentError escaping leaves a caller who catches the documented type
  // with an uncaught error. A recipient's advertised key is peer-supplied on
  // every path that reaches here, so this is reachable input, not a typo.
  final ({Uint8List ciphertext, Uint8List sharedSecret}) enc;
  try {
    enc = await kem.encapsulate(recipientPublicKey);
  } on ArgumentError catch (e) {
    throw PqSealException('encapsulation rejected the recipient key: $e');
  }

  // The version names the whole suite, so the KEM has to be the suite's KEM.
  // Nothing in the signature ties them together: `kem` and `version` are
  // independent arguments, and the default version means a caller reaches this
  // with a mismatched pair without naming a version at all. Compared by
  // encapsulation length rather than by asking the KEM what it is, because the
  // bytes are what an opener has to work from — it selects its KEM from the
  // version byte, so a mismatched seal produces a record no conformant reader
  // can open. Refused here for the same reason an unsupported version is
  // refused above.
  if (enc.ciphertext.length != row.suite.nEnc) {
    throw PqSealException(
        'version 0x${version.toRadixString(16)} is KEM '
        '0x${row.suite.kemId.toRadixString(16)}, whose encapsulation is '
        '${row.suite.nEnc} bytes; this KEM produced ${enc.ciphertext.length}');
  }

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
/// match what the sender supplied — [info] is required for the reason given on
/// [pqSeal], and passing the wrong one is indistinguishable from a tampered
/// envelope.
///
/// Throws [PqOpenException] on any failure (see [PqOpenFailure]).
Future<Uint8List> pqOpen(
  AtKemAlgorithm kem,
  Uint8List recipientSecretKey,
  Uint8List envelope, {
  required Uint8List info,
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

/// The AEAD key and nonce [pqSeal] derives from a KEM shared secret, exposed so
/// a conformance suite can check the schedule directly.
///
/// A second implementation that disagrees here produces envelopes this one
/// cannot open, and the failure arrives as an AEAD authentication error that
/// says nothing about which side is wrong. Comparing the schedule's own output
/// turns that into a one-line diff.
///
/// [version] selects the suite, so a caller can check a version this build
/// still reads but no longer emits. Every supported version now derives
/// through RFC 9180 §5.1, so the authority is the RFC and the working group's
/// vectors in `test/vectors/`.
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

/// Derives the AEAD key and nonce from the KEM [ss] per [version]'s table row,
/// using RFC 9180's own §5.1 schedule bound to the caller's [info].
_DerivedKey _deriveKeyAndNonce(Uint8List ss, int version, Uint8List? info) {
  final _SealVersion? row = _versions[version];
  if (row == null) {
    throw ArgumentError(
        'no key schedule for version 0x${version.toRadixString(16)} — this '
        'build knows ${pqSealSupportedVersions.map((v) => '0x${v.toRadixString(16)}').join(', ')}');
  }
  // RFC 9180 Base mode, verbatim, at every version. Both suites are checked
  // against the IETF HPKE working group's published vectors in
  // test/rfc9180_hpke_test.dart — bytes nobody here produced.
  final ks = hpkeKeyScheduleBase(row.suite, ss, info: info);
  return _DerivedKey(ks.key, ks.baseNonce);
}
