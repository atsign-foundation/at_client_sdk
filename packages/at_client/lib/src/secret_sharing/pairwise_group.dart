import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show
        AESKey,
        AesGcm256EncryptionAlgo,
        AtChopsUtil,
        HkdfSha256,
        InitialisationVector,
        SHA256HashingAlgo;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_client/src/secret_sharing/secure_group.dart';
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// Self-encryption [SecureGroup] v1, scoped to **(atSign, namespace)**.
///
/// Backed entirely by the secret-sharing substrate — no new storage. Epoch
/// keys live in the scope's namespace under reserved (`__`) names:
///
/// * `__rk.<epoch>.<kid>` → `{"v":1,"alg":"aes-256","key":"<b64-32B>"}` —
///   immutable, one per epoch key.
/// * `__rk.current` → `{"epoch":N,"kid":"<kid>","createdAt":"<iso>"}` — the
///   single mutable pointer; `SecretStore.putIfNewer` gives
///   newest-`createdAt`-wins convergence on arrival.
///
/// `kid = sha256(keyBytes)[:8 bytes]` hex — **kid is the truth, epoch an
/// ordering hint.** Two clients can concurrently mint "epoch N+1" with
/// different keys: both `__rk.<N+1>.<kidA>`/`<kidB>` survive (distinct
/// names), every ciphertext carries its own `(epoch, kid)`, and the pointer
/// converges. No coordination protocol.
@experimental
class PairwiseGroup implements SecureGroup {
  // Typed on the mixin (which is `on PairwiseClientRegistration`, so it
  // exposes both the roster and the sharing surface) rather than the
  // concrete AtClientSecretSharing — depends on the capability, and is
  // drivable by any composition of the mixins (incl. test harnesses).
  final PairwiseSecretSharing _sharing;
  final String atSign;

  /// The scope namespace this group governs.
  final String namespace;

  final RotationPolicy rotationPolicy;

  /// How long [open]/[seal] waits for a missing epoch key to arrive via the
  /// pull flow before giving up with [CryptoKeyUnavailableException].
  final Duration recoverTimeout;

  PairwiseGroup({
    required PairwiseSecretSharing sharing,
    required this.atSign,
    required this.namespace,
    this.rotationPolicy = const RotationPolicy(),
    this.recoverTimeout = const Duration(seconds: 30),
  }) : _sharing = sharing;

  static const String _rkPrefix = '__rk.';
  static const String _pointerName = '__rk.current';

  int _localEpoch = 0;

  @override
  String get groupId => 'self:$atSign:$namespace';

  @override
  int get currentEpoch => _localEpoch;

  String _rkName(int epoch, String kid) => '$_rkPrefix$epoch.$kid';

  /// `kid = sha256(keyBytes)[:8 bytes]` as lowercase hex (16 chars).
  @visibleForTesting
  static String kidOf(Uint8List keyBytes) =>
      // SHA256HashingAlgo.hash returns the full digest as lowercase hex; the
      // first 16 hex chars are the first 8 bytes.
      SHA256HashingAlgo().hash(keyBytes).substring(0, 16);

  ({int epoch, String kid, DateTime createdAt})? _readPointer() {
    final s = _sharing.secretStore.getSecret(namespace, _pointerName);
    if (s == null) return null;
    final j = jsonDecode(s.value) as Map;
    return (
      epoch: j['epoch'] as int,
      kid: j['kid'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }

  Uint8List? _epochKeyBytes(int epoch, String kid) {
    final s = _sharing.secretStore.getSecret(namespace, _rkName(epoch, kid));
    if (s == null) return null;
    return base64Decode((jsonDecode(s.value) as Map)['key'] as String);
  }

  /// Resolves the key to seal/export under: ensures a current epoch exists
  /// (minting epoch 1 if none), optionally rotating first when the policy's
  /// [RotationPolicy.maxEpochAge] is exceeded ([rotateOnAge]). Recovers the
  /// key bytes via the pull flow if the pointer names one not held locally.
  Future<({int epoch, String kid, Uint8List key})> _currentKey(
      {required bool rotateOnAge}) async {
    var ptr = _readPointer();
    final maxAge = rotationPolicy.maxEpochAge;
    if (ptr == null) {
      await rotate();
      ptr = _readPointer()!;
    } else if (rotateOnAge &&
        maxAge != null &&
        DateTime.now().toUtc().difference(ptr.createdAt) > maxAge) {
      await rotate();
      ptr = _readPointer()!;
    }
    if (ptr.epoch > _localEpoch) _localEpoch = ptr.epoch;
    final key = _epochKeyBytes(ptr.epoch, ptr.kid) ??
        await _recover(ptr.epoch, ptr.kid);
    return (epoch: ptr.epoch, kid: ptr.kid, key: key);
  }

  @override
  Future<Sealed> seal(Uint8List plaintext) async {
    final cur = await _currentKey(rotateOnAge: true);
    final iv =
        AtChopsUtil.generateRandomIV(AesGcm256EncryptionAlgo.nonceLength);
    final ct = await AesGcm256EncryptionAlgo(AESKey(base64Encode(cur.key)))
        .encrypt(plaintext, iv: iv);
    return Sealed(
        epoch: cur.epoch, kid: cur.kid, iv: iv.ivBytes, ciphertext: ct);
  }

  @override
  Future<Uint8List> open(Sealed sealed) async {
    final key = _epochKeyBytes(sealed.epoch, sealed.kid) ??
        await _recover(sealed.epoch, sealed.kid);
    return AesGcm256EncryptionAlgo(AESKey(base64Encode(key)))
        .decrypt(sealed.ciphertext, iv: InitialisationVector(sealed.iv));
  }

  /// Pull-then-wait recovery for a missing epoch key: broadcast a request to
  /// the namespace's clients, wait for the named secret to arrive, re-check.
  Future<Uint8List> _recover(int epoch, String kid) async {
    final name = _rkName(epoch, kid);
    try {
      await _sharing.requestSecretsFromNamespace(namespace, names: [name]);
      await _sharing.waitForSecret(namespace, name, timeout: recoverTimeout);
    } on Exception {
      // fall through to the definitive local check
    }
    final key = _epochKeyBytes(epoch, kid);
    if (key == null) {
      throw CryptoKeyUnavailableException(
          'epoch key $name for group $groupId is unavailable');
    }
    return key;
  }

  @override
  Future<void> rotate({Set<String> excludeEnrollmentIds = const {}}) async {
    // 32 secure-random bytes from the same CSPRNG the envelope crypto uses.
    final keyBytes = AtChopsUtil.generateRandomIV(32).ivBytes;
    final keyB64 = base64Encode(keyBytes);
    final kid = kidOf(keyBytes);

    final ptr = _readPointer();
    // Monotonic from the max epoch seen (pointer or locally adopted) so a
    // regressed pointer can't make us mint a lower epoch.
    final base = (ptr?.epoch ?? 0) > _localEpoch ? ptr!.epoch : _localEpoch;
    final epoch = base + 1;
    final now = DateTime.now().toUtc();

    final rkSecret = Secret(
      namespace: namespace,
      name: _rkName(epoch, kid),
      value: jsonEncode({'v': 1, 'alg': 'aes-256', 'key': keyB64}),
      createdAt: now,
    );
    final pointerSecret = Secret(
      namespace: namespace,
      name: _pointerName,
      value: jsonEncode(
          {'epoch': epoch, 'kid': kid, 'createdAt': now.toIso8601String()}),
      createdAt: now,
    );
    await _sharing.secretStore.putSecret(rkSecret, allowReservedName: true);
    await _sharing.secretStore
        .putSecret(pointerSecret, allowReservedName: true);
    _localEpoch = epoch;

    final members = await _sharing.discoverClients(
        namespace: namespace, excludeEnrollmentIds: excludeEnrollmentIds);
    for (final member in members) {
      await _sharing.shareSecretWith(member, rkSecret);
      await _sharing.shareSecretWith(member, pointerSecret);
    }
  }

  @override
  Future<Uint8List> export(String label, int length) async {
    // Export must NOT rotate-on-age — two members deriving at different times
    // must land on the same epoch. It only mints epoch 1 if none exists yet.
    final cur = await _currentKey(rotateOnAge: false);
    return HkdfSha256.deriveKey(
      cur.key,
      salt: Uint8List.fromList(utf8.encode(groupId)),
      info: Uint8List.fromList(utf8.encode(label)),
      length: length,
    );
  }
}
