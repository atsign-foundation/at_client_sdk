import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('CryptoRollout');

/// The operator's controls for this atSign's post-quantum rollout.
///
/// Adopting the post-quantum data path is a **negotiated, gated rollout, not a
/// flag day**: clients are rebuilt, they publish their namespace keys while
/// still writing legacy, and only when every one of an atSign's enrollments is
/// an upgraded build does anything start writing the new scheme. What decides
/// that last step is the capability marker this class publishes.
///
/// **The flip is the only operator judgement call in the whole migration.**
/// Everything else is negotiated from published evidence; declaring readiness
/// is a statement about software the SDK cannot see — whether some device
/// somewhere is still running last year's build. Declaring it too early is the
/// one way to write data an enrollment of your own atSign cannot read. Nothing
/// is lost that was already written: reads stay universal, and legacy records
/// keep opening forever.
@experimental
class CryptoRollout {
  final AtClient _atClient;
  final PublishedCapabilities capabilities;

  CryptoRollout(this._atClient, {PublishedCapabilities? capabilities})
      : capabilities =
            capabilities ?? PublishedCapabilities.forClient(_atClient);

  /// Every scheme a client of this build can *read*.
  ///
  /// The legacy provider is always in it — it is never unregistered, because
  /// history has to keep opening — plus whatever the resolved [CryptoConfig]
  /// registers. This is what a fleet advertises once its operator declares it
  /// ready, and it is deliberately the *read* set: a marker answers "can every
  /// enrollment open a record written this way", which has nothing to do with
  /// what any of them chooses to write.
  Set<String> get readableSchemes => {
        legacyCryptoProviderId,
        ...CryptoConfig.forClient(_atClient).providers.map((p) => p.id),
      };

  /// Publish `not-ready` for [namespace] — this atSign reads legacy and nothing
  /// else — unless something is already advertised for it.
  ///
  /// This is the step every upgraded client takes at start, and the
  /// already-advertised guard is what makes it safe to run unconditionally: a
  /// client that published `{legacy}` over its operator's readiness
  /// declaration would demote the whole atSign on every restart, and the
  /// operator would have to keep re-declaring it. The guard checks **every
  /// level** of a composed namespace, so a not-ready seeded at
  /// `d.c.b.a` cannot silently undo a readiness declared at `a` — the two
  /// intersect, and the deeper one would win.
  ///
  /// Returns whether it published.
  Future<bool> publishNotReadyIfAbsent(String namespace) async {
    final owner = _atClient.getCurrentAtSign();
    if (owner == null) return false;
    if (await capabilities.advertisedBy(owner, namespace) != null) return false;
    await publishNotReady(namespace);
    return true;
  }

  /// State that this atSign's fleet reads **legacy only**.
  ///
  /// Also how readiness is withdrawn — an operator who declared too early, or
  /// who is about to bring an old build back online, publishes this. Withdrawal
  /// is not retroactive: records already written under the post-quantum path
  /// stay that way, and an enrollment that cannot read them still cannot.
  Future<void> publishNotReady(String namespace) => capabilities
      .publish(namespace: namespace, schemes: {legacyCryptoProviderId});

  /// State that **every** enrollment of this atSign can read [schemes],
  /// defaulting to everything a client of this build reads.
  ///
  /// The one thing to check before calling it: that no enrollment of this
  /// atSign is still running a build older than this one. There is no
  /// mechanical test for that — an old build publishes nothing to be found, so
  /// its absence proves nothing — which is why this is a declaration rather
  /// than a detection.
  Future<void> declareReady(String namespace, {Set<String>? schemes}) async {
    final declared = schemes ?? readableSchemes;
    _logger.shout(
        'Declaring $namespace ready for ${declared.join(', ')}. From now on '
        'senders may write this atSign records that only those schemes open — '
        'any enrollment still running an older build will not be able to read '
        'what arrives after this point.');
    await capabilities.publish(namespace: namespace, schemes: declared);

    // A marker at an ancestor is intersected with this one, so declaring
    // readiness deep while an ancestor still says legacy-only changes nothing.
    // Saying so here beats leaving an operator to wonder why the flip did not
    // take.
    final owner = _atClient.getCurrentAtSign();
    final effective = owner == null
        ? null
        : await capabilities.advertisedBy(owner, namespace);
    if (effective != null && !effective.containsAll(declared)) {
      _logger.warning(
          'Readiness for $namespace is held back by a marker on a broader '
          'namespace: senders will see ${effective.join(', ')}. Declare the '
          'broader namespace ready too, or the deeper declaration has no '
          'effect.');
    }
  }

  /// What [atSign]'s fleet advertises it can read for [namespace], or null if
  /// it has advertised nothing — the diagnostic behind "why did that write go
  /// out legacy".
  Future<Set<String>?> advertisedBy(String atSign, String namespace) =>
      capabilities.advertisedBy(atSign, namespace);
}
