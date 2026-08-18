import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_commons/at_commons.dart' show AtEncryptionException;

/// An nskey found for a namespace, and the namespace it was actually found at.
///
/// [namespace] is what the caller needs afterwards — it scopes the content key,
/// addresses the conveyance record, and is written to the value's
/// `appMetadata.ckNs`. It is a suffix of (or equal to) the namespace asked for.
typedef ResolvedNskey = ({
  String namespace,
  String nskeyKid,
  List<int> publicKey,
  String alg,
});

/// Finds which level of a nested namespace holds the nskey to seal to.
///
/// A namespace nests — `d.c.b.a` sits under `c.b.a`, `b.a` and `a` — and a key
/// may live at any level. Resolution walks **most-specific-first** and takes the
/// first hit: `d.c.b.a`, then `c.b.a`, then `b.a`, then `a`. An exhausted walk
/// is the cold-start case.
///
/// Walking up is safe because it mirrors the atServer's own authorisation rule:
/// an enrollment approved for `a` may access `d.c.b.a`, so sealing to a broader
/// key can never let an enrollment read something the server would have
/// withheld. The crypto gate never widens past the transport gate.
///
/// It is also not optional. `AtCollection` composes a sub-collection's namespace
/// as `<subName>.<parentId>.<ns>` with a **per-item** id, so an exact-match rule
/// would need a keypair, a published advertisement and a per-enrollment
/// conveyance for every item ever created.
class NskeyResolver {
  final NskeyKeyRing keyRing;

  /// How long a *miss* is remembered. Hits are the ring's business — it already
  /// caches those with its own freshness policy — but a miss is not cached
  /// anywhere below, so without this a repeated write to the same namespace
  /// re-probes every level it does not hold a key at.
  final Duration missMemory;

  /// Which of an owner's advertised KEM keys this client is willing to seal
  /// to, strongest first — `AtClientPreference.sealsToKeyAlgorithms`.
  ///
  /// Defaulted here because a caller constructing a resolver without a
  /// preference in hand has no basis to choose, and everything this build can
  /// seal under refuses nobody — which is what a caller that said nothing
  /// meant. A client passes its preference's list.
  final List<String> sealsToKeyAlgorithms;

  NskeyResolver(this.keyRing,
      {this.missMemory = const Duration(minutes: 15),
      this.sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos});

  /// `owner|namespace` → when it was found to hold no key.
  ///
  /// Deliberately **only misses**. A remembered *hit* would be the dangerous
  /// one: it would let a resolution skip straight to a broader level and never
  /// probe the deeper ones, so a key sitting at `medical.notes` would go unseen
  /// merely because some earlier write had warmed `notes`. Skipping a probe can
  /// only ever lose a deeper key; skipping it for a level we have just been told
  /// is empty cannot.
  final Map<String, DateTime> _missedAt = {};

  /// The nskey to seal to for a value in [namespace] owned by [owner], or null
  /// if no level has one.
  Future<ResolvedNskey?> resolve(String owner, String namespace) async {
    for (final candidate in candidates(namespace)) {
      if (_recentlyMissed(owner, candidate)) continue;

      final hit = await keyRing.currentPublic(owner, candidate);
      if (hit != null) {
        _missedAt.remove(_scope(owner, candidate));
        final key = hit.usableFor(sealsToKeyAlgorithms);
        if (key == null) {
          // Refused rather than walked past. Walking on would seal under a
          // BROADER namespace's key — a different content-key scope than the
          // caller asked for — arrived at silently because of a rule this
          // client set. And it is refused rather than reported as a cold
          // start, or a deployment that narrowed the list reads its own
          // configuration as the recipient having published nothing.
          throw AtEncryptionException(
              '$owner:$candidate advertises '
              '${hit.keys.map((k) => k.alg).toSet().join(', ')} and this '
              'client will seal to ${sealsToKeyAlgorithms.join(', ')} - no '
              'algorithm in common, so nothing is sealed. Widen '
              'AtClientPreference.sealsToKeyAlgorithms to reach this owner');
        }
        return (
          namespace: candidate,
          nskeyKid: key.kid,
          publicKey: key.pubBytes,
          alg: key.alg,
        );
      }
      _missedAt[_scope(owner, candidate)] = DateTime.now();
    }
    return null;
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
