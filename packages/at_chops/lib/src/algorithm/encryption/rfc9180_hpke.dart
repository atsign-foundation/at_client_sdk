import 'dart:typed_data';

import '../hashing/hkdf_core.dart';
import 'at_aead.dart';

/// RFC 9180 HPKE, **Base mode**, single-shot.
///
/// This is the real thing, unlike `pqSeal`'s `atPQv1-base` — the key schedule
/// below is RFC 9180 §5.1 verbatim, and its outputs are checked against the
/// IETF HPKE working group's published vectors for KEM `0x647A` in
/// `test/rfc9180_hpke_test.dart`. Those are bytes nobody at Atsign produced,
/// which is the whole reason for having it.
///
/// Only Base mode is implemented, and only single-shot. HPKE's PSK modes,
/// sequence numbers, `base_nonce ^ seq` and multi-message contexts buy nothing
/// here: every seal encapsulates afresh, so each `(key, nonce)` pair is used
/// for exactly one message. `exporterSecret` is derived because the key
/// schedule produces it and a conformance vector checks it, not because
/// anything consumes it yet.
///
/// The KEM is not implemented here. HPKE treats it as a parameter, and X-Wing
/// lives in `x_wing_pure_dart.dart`; this file takes the shared secret the KEM
/// produced.

/// An HPKE ciphersuite: the three IANA code points that identify it.
///
/// These are the numbers in `suite_id`, so getting one wrong changes every
/// derived key rather than failing loudly — which is why the published vectors
/// carry `suite_id` and the tests assert it directly.
class HpkeSuite {
  /// IANA HPKE KEM id. `0x647A` is the X-Wing / MLKEM768-X25519 hybrid.
  final int kemId;

  /// IANA HPKE KDF id. `0x0001` is HKDF-SHA256.
  final int kdfId;

  /// IANA HPKE AEAD id. `0x0003` is ChaCha20-Poly1305; `0x0002` is
  /// AES-256-GCM.
  final int aeadId;

  /// AEAD key length in bytes.
  final int nk;

  /// AEAD nonce length in bytes.
  final int nn;

  /// KDF output length in bytes — 32 for SHA-256.
  final int nh;

  const HpkeSuite({
    required this.kemId,
    required this.kdfId,
    required this.aeadId,
    required this.nk,
    required this.nn,
    required this.nh,
  });

  /// X-Wing + HKDF-SHA256 + ChaCha20-Poly1305.
  ///
  /// ChaCha20-Poly1305 rather than AES-256-GCM because it is the only AEAD the
  /// HPKE working group publishes `0x647A` vectors for. Choosing AES-GCM would
  /// mean shipping a suite with no published end-to-end vector, and the FIPS
  /// story that might have justified it is unavailable anyway: X25519 key
  /// agreement has no approved path, so this hybrid is unclaimable under FIPS
  /// whatever AEAD sits on top.
  static const xWingHkdfSha256ChaCha20Poly1305 = HpkeSuite(
    kemId: 0x647A,
    kdfId: 0x0001,
    aeadId: 0x0003,
    nk: 32,
    nn: 12,
    nh: 32,
  );

  /// ML-KEM-1024 alone + HKDF-SHA384 + AES-256-GCM: the no-hybrid option.
  ///
  /// This is the only published HPKE suite for KEM `0x0042` at a 256-bit AEAD,
  /// so it is the one that comes with a third-party end-to-end vector. It is
  /// also the combination CNSA 2.0 names — ML-KEM-1024 with SHA-384 and
  /// AES-256.
  ///
  /// `nh` is 48 here rather than 32, because the exporter secret is a full
  /// KDF output and this KDF is SHA-384.
  static const mlKem1024HkdfSha384Aes256Gcm = HpkeSuite(
    kemId: 0x0042,
    kdfId: 0x0002,
    aeadId: 0x0002,
    nk: 32,
    nn: 12,
    nh: 48,
  );

  /// `suite_id = "HPKE" || I2OSP(kem_id, 2) || I2OSP(kdf_id, 2) ||
  /// I2OSP(aead_id, 2)` (RFC 9180 §5.1).
  Uint8List get suiteId => Uint8List.fromList([
        0x48, 0x50, 0x4b, 0x45, // "HPKE"
        (kemId >> 8) & 0xff, kemId & 0xff,
        (kdfId >> 8) & 0xff, kdfId & 0xff,
        (aeadId >> 8) & 0xff, aeadId & 0xff,
      ]);

  /// The KDF [kdfId] names — the one mapping [labeledExtract] and
  /// [labeledExpand] both dispatch through.
  Hkdf get kdf => switch (kdfId) {
        _kdfHkdfSha256 => Hkdf.sha256,
        _kdfHkdfSha384 => Hkdf.sha384,
        _ => throw ArgumentError(
            'no HPKE KDF for id 0x${kdfId.toRadixString(16)}'),
      };

  /// The AEAD [aeadId] names. Carried here so a version table can pick a
  /// suite and get its cipher with it, instead of re-deriving the cipher
  /// from the version byte at every call site.
  AtAeadAlgorithm get aead => switch (aeadId) {
        0x0002 => const AesGcm256Aead(),
        0x0003 => const ChaCha20Poly1305Aead(),
        _ => throw ArgumentError(
            'no HPKE AEAD for id 0x${aeadId.toRadixString(16)}'),
      };
}

/// What RFC 9180's key schedule produces.
typedef HpkeKeySchedule = ({
  Uint8List key,
  Uint8List baseNonce,
  Uint8List exporterSecret,
});

/// The HPKE version label prefixed to every labeled extract and expand.
final Uint8List _hpkeV1 = Uint8List.fromList('HPKE-v1'.codeUnits);

Uint8List _cat(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

/// RFC 9180 §4: `LabeledExtract(salt, label, ikm)`.
///
/// `labeled_ikm = "HPKE-v1" || suite_id || label || ikm`, then HKDF-Extract.
/// The suite id inside the label is what stops one ciphersuite's keys being
/// usable as another's.
Uint8List labeledExtract(
  HpkeSuite suite,
  Uint8List salt,
  String label,
  Uint8List ikm,
) {
  final labeled = _cat([_hpkeV1, suite.suiteId, label.codeUnits, ikm]);
  return suite.kdf.extract(labeled, salt: salt);
}

/// IANA HPKE KDF id `0x0001`.
const int _kdfHkdfSha256 = 0x0001;

/// IANA HPKE KDF id `0x0002`.
const int _kdfHkdfSha384 = 0x0002;

/// RFC 9180 §4: `LabeledExpand(prk, label, info, L)`.
///
/// `labeled_info = I2OSP(L, 2) || "HPKE-v1" || suite_id || label || info`.
/// The two-byte length prefix is why HPKE's labels cannot collide the way a
/// raw concatenation's can.
Uint8List labeledExpand(
  HpkeSuite suite,
  Uint8List prk,
  String label,
  Uint8List info,
  int length,
) {
  final labeled = _cat([
    [(length >> 8) & 0xff, length & 0xff],
    _hpkeV1,
    suite.suiteId,
    label.codeUnits,
    info,
  ]);
  return suite.kdf.expand(prk, info: labeled, length: length);
}

/// RFC 9180 §5.1 `KeySchedule` in Base mode (`mode = 0x00`).
///
/// Base mode fixes `psk` and `psk_id` to empty, so both still enter the
/// schedule — as the hashes of empty strings — rather than being skipped. A
/// port that omits them derives different keys and the failure arrives as an
/// AEAD authentication error.
HpkeKeySchedule hpkeKeyScheduleBase(
  HpkeSuite suite,
  Uint8List sharedSecret, {
  Uint8List? info,
}) {
  final empty = Uint8List(0);

  final pskIdHash = labeledExtract(suite, empty, 'psk_id_hash', empty);
  final infoHash = labeledExtract(suite, empty, 'info_hash', info ?? empty);
  // key_schedule_context = mode || psk_id_hash || info_hash, mode = 0x00.
  final context = _cat([
    [0x00],
    pskIdHash,
    infoHash,
  ]);

  final secret = labeledExtract(suite, sharedSecret, 'secret', empty);

  return (
    key: labeledExpand(suite, secret, 'key', context, suite.nk),
    baseNonce: labeledExpand(suite, secret, 'base_nonce', context, suite.nn),
    exporterSecret: labeledExpand(suite, secret, 'exp', context, suite.nh),
  );
}
