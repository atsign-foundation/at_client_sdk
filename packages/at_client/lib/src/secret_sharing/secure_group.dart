import 'dart:typed_data' show Uint8List;

import 'package:meta/meta.dart' show experimental;

/// An AEAD-sealed blob produced by [SecureGroup.seal]: the ciphertext plus
/// the coordinates needed to find the key that opens it. Maps 1:1 onto the
/// `group` CryptoProvider's `AppMetadata.additional`
/// (`{epoch, kid, iv}` + the ciphertext).
@experimental
class Sealed {
  final int epoch;

  /// Names the epoch key: `sha256(keyBytes)[:8 bytes]` as hex (16 chars).
  final String kid;

  /// 12-byte AES-GCM nonce.
  final Uint8List iv;

  final Uint8List ciphertext;

  const Sealed({
    required this.epoch,
    required this.kid,
    required this.iv,
    required this.ciphertext,
  });
}

/// When a group mints a new data ("epoch") key.
@experimental
class RotationPolicy {
  /// Rotate lazily at [SecureGroup.seal] when the current epoch key is older
  /// than this. `null` = never rotate on age (manual / revocation only).
  final Duration? maxEpochAge;

  /// Whether a revocation should trigger a rotation. Advisory: the caller
  /// performs the revocation rotation by invoking [SecureGroup.rotate] with
  /// the revoked enrollment excluded; this flag documents the intent.
  final bool rotateOnRevocation;

  const RotationPolicy({this.maxEpochAge, this.rotateOnRevocation = true});
}

/// Thrown by [SecureGroup.open] when the epoch key a ciphertext names cannot
/// be resolved — not held locally and not recovered via the pull flow within
/// the recovery timeout. The `group` CryptoProvider surfaces this to the
/// app through `CryptoPolicy.onDecryptFailed`.
@experimental
class CryptoKeyUnavailableException implements Exception {
  final String message;

  CryptoKeyUnavailableException(this.message);

  @override
  String toString() => 'CryptoKeyUnavailableException: $message';
}

/// A set of clients that share rotating symmetric "epoch" keys and can seal
/// / open data and derive named secrets under them.
///
/// v1 ([PairwiseGroup]) is **self-encryption**: the members are the clients
/// of one atSign authorized for one namespace, and epoch keys ride the
/// secret-sharing substrate. v2 (Phase 5) will be an MLS-backed group with
/// explicit add/remove. The contract is kept minimal and engine-agnostic so
/// the v1→v2 swap is an engine change, not a redesign.
@experimental
abstract class SecureGroup {
  /// Deterministic id, e.g. `self:<atSign>:<namespace>`, so concurrent
  /// first-use by two clients converges on the same group.
  String get groupId;

  /// The epoch new data is sealed under (`0` before the first rotation).
  int get currentEpoch;

  /// AEAD-seal [plaintext] under the current epoch key — rotating first if
  /// the [RotationPolicy] says the epoch is stale, or minting epoch 1 on
  /// first use.
  Future<Sealed> seal(Uint8List plaintext);

  /// Reverse [seal]. Resolves the epoch key by `(epoch, kid)`; on a local
  /// miss runs the pull-then-wait recovery, then throws
  /// [CryptoKeyUnavailableException] if still unavailable.
  Future<Uint8List> open(Sealed sealed);

  /// Mint a new epoch key and distribute it to current members, excluding
  /// [excludeEnrollmentIds] (revocation). Any member may call this; the
  /// `kid`-is-truth model converges concurrent rotations without a protocol.
  Future<void> rotate({Set<String> excludeEnrollmentIds});

  /// HKDF-SHA256 a deterministic secret bound to the current epoch key, for
  /// app use (e.g. NoPorts session keys). The same `(label, length)` at the
  /// same epoch yields identical bytes for every member.
  Future<Uint8List> export(String label, int length);
}
