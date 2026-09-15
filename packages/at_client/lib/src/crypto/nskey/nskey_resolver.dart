import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_commons/at_commons.dart' show AtEncryptionException;

/// An nskey found for a namespace, and the namespace it was actually found at.
///
/// [namespace] is a suffix of (or equal to) the namespace asked for, and is what
/// scopes the content key.
typedef ResolvedNskey = ({
  String namespace,
  String nskeyKid,
  List<int> publicKey,
  String alg,
});

/// Finds which level of a nested namespace holds the nskey to seal to.
///
/// Resolution walks most-specific-first and takes the first hit — `d.c.b.a`,
/// then `c.b.a`, then `b.a`, then `a` — with an exhausted walk the cold-start
/// case; walking up never widens access, the atServer already letting an
/// enrollment approved for `a` reach `d.c.b.a`.
class NskeyResolver {
  final NskeyKeyRing keyRing;

  /// How long a *miss* is remembered. Hits are not cached here; the key ring
  /// caches those under its own freshness policy.
  final Duration missMemory;

  /// Which of an owner's advertised KEM keys this client is willing to seal
  /// to, strongest first — `AtClientPreference.sealsToKeyAlgorithms`.
  final List<String> sealsToKeyAlgorithms;

  NskeyResolver(this.keyRing,
      {this.missMemory = const Duration(minutes: 15),
      this.sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos});

  /// `owner|namespace` → when it was found to hold no key.
  ///
  /// Misses only: a remembered hit would let a walk skip a deeper level and miss
  /// a key sitting there.
  final Map<String, DateTime> _missedAt = {};

  /// The nskey to seal to for a value in [namespace] owned by [owner], or null
  /// if no level has one.
  ///
  /// A remembered miss never decides a null: when no level resolves, every level
  /// [missMemory] let the first walk skip is probed for real before the caller
  /// is told no.
  Future<ResolvedNskey?> resolve(String owner, String namespace) async {
    final first = await _walk(owner, namespace, useMemory: true);
    if (first.hit != null || !first.skipped) return first.hit;
    return (await _walk(owner, namespace, useMemory: false)).hit;
  }

  /// One most-specific-first pass, reporting whether [missMemory] made it skip
  /// anything — which is what tells [resolve] a null is not yet trustworthy.
  Future<({ResolvedNskey? hit, bool skipped})> _walk(
      String owner, String namespace,
      {required bool useMemory}) async {
    var skipped = false;
    for (final candidate in candidates(namespace)) {
      if (useMemory && _recentlyMissed(owner, candidate)) {
        skipped = true;
        continue;
      }

      final hit = await keyRing.currentPublic(owner, candidate);
      if (hit != null) {
        _missedAt.remove(_scope(owner, candidate));
        final key = hit.usableFor(sealsToKeyAlgorithms);
        if (key == null) {
          // NOTE: refuse rather than walk on — a broader level's key silently
          // changes the content-key scope the caller asked for — and refuse
          // rather than report a cold start, or a narrowed algorithm list reads
          // as the recipient having published nothing.
          throw AtEncryptionException('$owner:$candidate advertises '
              '${hit.keys.map((k) => k.alg).toSet().join(', ')} and this '
              'client will seal to ${sealsToKeyAlgorithms.join(', ')} - no '
              'algorithm in common, so nothing is sealed. Widen '
              'AtClientPreference.sealsToKeyAlgorithms to reach this owner');
        }
        return (
          hit: (
            namespace: candidate,
            nskeyKid: key.kid,
            publicKey: key.pubBytes,
            alg: key.alg,
          ),
          skipped: skipped,
        );
      }
      _missedAt[_scope(owner, candidate)] = DateTime.now();
    }
    return (hit: null, skipped: skipped);
  }

  /// Every level of [namespace], most specific first:
  /// `d.c.b.a`, `c.b.a`, `b.a`, `a`.
  static Iterable<String> candidates(String namespace) sync* {
    var remaining = namespace;
    while (true) {
      yield remaining;
      final dot = remaining.indexOf('.');
      if (dot < 0) return;
      remaining = remaining.substring(dot + 1);
    }
  }

  bool _recentlyMissed(String owner, String namespace) {
    final at = _missedAt[_scope(owner, namespace)];
    if (at == null) return false;
    if (DateTime.now().difference(at) < missMemory) return true;
    _missedAt.remove(_scope(owner, namespace));
    return false;
  }

  static String _scope(String owner, String namespace) => '$owner|$namespace';
}
