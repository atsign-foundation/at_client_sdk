import 'dart:convert';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/nskey/nskey_resolver.dart';
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart' show experimental, visibleForTesting;

final _logger = AtSignLogger('PublishedCapabilities');

/// The at-key an atSign advertises its fleet's readable schemes under.
///
/// Shaped exactly like the nskey advertisement — `public:__`, so an
/// unauthenticated scan cannot enumerate which namespaces an atSign uses while
/// an exact `plookup` still serves the marker to any sender that knows the
/// namespace. A sender must be able to read it cross-atSign before it writes,
/// so anything less reachable than the nskey it pairs with would be useless.
@experimental
AtKey capabilityAdvertisementKey(String owner, String namespace) => AtKey()
  ..key = '__capability'
  ..namespace = namespace
  ..sharedBy = owner
  ..metadata = (Metadata()..isPublic = true);

/// What an atSign's fleet advertises it can read for one namespace.
///
/// A **set of provider ids**, not a ready/not-ready boolean. A boolean cannot
/// say *which* schemes are readable, so it cannot survive a second
/// post-quantum scheme — and the whole point of a provider id naming every
/// algorithm a reader needs code for is that schemes can then coexist and be
/// rolled. Ready/not-ready is the degenerate case: "is the post-quantum pair in
/// the set".
///
/// [declaredAt] is when the publishing client stated it, not when it was
/// fetched. It is diagnostic: the flip is an operator judgement call, and the
/// first question asked of a fleet that lost access is when readiness was
/// declared.
@experimental
typedef FleetCapability = ({Set<String> schemes, DateTime declaredAt});

/// Checks that a fetched capability marker really came from the atSign that
/// claims it.
///
/// The same two gates the nskey advertisement stands behind: the atServer
/// accepts the write only from an enrollment authorised for the namespace, and
/// the envelope is signed with that enrollment's APKAM keypair, verified
/// against the `_apsk` only it may publish. An unsigned marker is refused
/// rather than trusted, because a marker an attacker can write is a marker that
/// can *demote* every sender to legacy — a downgrade attack that needs no key
/// material at all.
@experimental
abstract class CapabilityVerifier {
  /// Return the capability carried by [payload], or throw if it cannot be
  /// trusted as [owner]'s.
  Future<FleetCapability> verify(String owner, String payload);
}

/// Verifies a marker's APKAM signature against the `_apsk` the signing
/// enrollment published under [owner]'s atSign.
@experimental
class ApkamSignedCapabilities implements CapabilityVerifier {
  final AtClientEnvelopeSigner _signer;

  ApkamSignedCapabilities(AtClient atClient)
      : _signer = AtClientEnvelopeSigner(atClient);

  @override
  Future<FleetCapability> verify(String owner, String payload) async {
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(payload) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw AtSigningVerificationException(
          'the capability marker for $owner is not JSON: ${e.message}');
    }
    // Every field the verify reads, checked up front: a missing one otherwise
    // surfaces as a cast error, which reads like a bug rather than the refusal
    // it is.
    if (['signature', 'enrollmentId', 'signingAlgo', 'hashingAlgo']
        .any((field) => envelope[field] is! String)) {
      throw AtSigningVerificationException(
          'the capability marker for $owner carries no APKAM signature, so any '
          'sender could be told this atSign reads nothing but legacy');
    }

    await _signer.verifyEnvelopeSignature(envelope, signerAtSign: owner);

    final advertised = envelope['payload'];
    if (advertised is! Map) {
      throw AtSigningVerificationException(
          'the capability marker for $owner has a signature over a payload '
          'that is not a capability');
    }
    final schemes = advertised['schemes'];
    if (schemes is! List) {
      throw AtSigningVerificationException(
          'the capability marker for $owner names no scheme set');
    }
    return (
      schemes: {for (final id in schemes) '$id'},
      declaredAt:
          DateTime.tryParse('${advertised['declaredAt']}') ?? DateTime(0),
    );
  }
}

/// Reads and publishes the per-`(atSign, namespace)` capability marker that
/// scheme negotiation runs on.
///
/// A sender asks this what a destination's fleet can read; a client publishing
/// its own atSign's marker states what every enrollment of that atSign can
/// read — **not** what the publishing client alone can. The gap between those
/// two sentences is the entire rollout: an upgraded client publishes
/// `{legacy}` because a sibling may still be an old build, and only the
/// operator's declaration says otherwise.
@experimental
class PublishedCapabilities {
  final AtClient _atClient;
  final CapabilityVerifier verifier;
  final AtClientEnvelopeSigner _signer;

  /// How long a fetched marker is trusted before it is re-fetched.
  ///
  /// This bounds how long a *flip* goes unnoticed, in both directions: a
  /// sender keeps writing legacy for up to this long after a destination
  /// declares readiness, and — the direction that matters — keeps writing
  /// post-quantum for up to this long after a destination withdraws it.
  final Duration ttl;

  /// How far past [ttl] a *failed* re-fetch may keep serving the answer it
  /// already has.
  ///
  /// A blip should not change what a client writes. Past the grace the answer
  /// is dropped rather than held, which returns the sender to its configured
  /// default — the conservative direction, since that default is legacy for
  /// every client that has not deliberately chosen otherwise.
  final Duration staleGrace;

  PublishedCapabilities(
    this._atClient, {
    CapabilityVerifier? verifier,
    this.ttl = const Duration(minutes: 15),
    this.staleGrace = const Duration(minutes: 15),
  })  : verifier = verifier ?? ApkamSignedCapabilities(_atClient),
        _signer = AtClientEnvelopeSigner(_atClient);

  /// The instance [atClient] negotiates and publishes through.
  ///
  /// One per client, because the answers are cached and a cache is only useful
  /// if the thing that *reads* it for a write is the same instance the operator
  /// flip *invalidates*. An [Expando] rather than a field, for the reason
  /// `CryptoConfig.forClient` uses one: an `AtClientPreference` is routinely
  /// shared across atSigns, and this is per-atSign state.
  static PublishedCapabilities forClient(AtClient atClient) =>
      _perClient[atClient] ??= PublishedCapabilities(atClient);

  static final Expando<PublishedCapabilities> _perClient =
      Expando('PublishedCapabilities.forClient');

  /// Give [atClient] a specific instance — a seeded one, in a test that must
  /// negotiate without an atServer to fetch markers from.
  @visibleForTesting
  static void setForClient(
          AtClient atClient, PublishedCapabilities capabilities) =>
      _perClient[atClient] = capabilities;

  /// Answer as though [owner] had published [schemes] for [namespace], without
  /// a round trip. The seeded answer expires with the ordinary [ttl].
  @visibleForTesting
  void seed(String owner, String namespace, Set<String> schemes) => _record(
      _scope(owner, namespace),
      (schemes: schemes, declaredAt: DateTime.now().toUtc()));

  /// `owner|namespace` → the last answer and when it was fetched. A *miss* is
  /// cached too: "this atSign has published nothing" is the common answer
  /// during the rollout, and re-asking on every write would put a round trip
  /// to someone else's atServer on the write path.
  final Map<String, ({FleetCapability? capability, DateTime fetchedAt})>
      _fetched = {};

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  /// What [owner]'s fleet can read for [namespace], or null when it has
  /// advertised nothing at any level of it.
  ///
  /// Null is *no evidence*, which is not the same as "legacy only" and must not
  /// be collapsed into it by the caller: a fleet that has published nothing is
  /// indistinguishable from one whose atServer could not be reached, and the
  /// two deserve different treatment from the two sides of a negotiation.
  ///
  /// **Every level of a composed namespace that carries a marker is
  /// intersected**, not just the first hit. A record at `d.c.b.a` is readable
  /// by enrollments authorised for `d.c.b.a` *or* any ancestor, so the readers
  /// are the union of those fleets and the schemes they all support are the
  /// intersection of what each advertises. Taking the first hit while walking
  /// up would describe a subset of the readers and silently exclude the
  /// deepest, most narrowly authorised enrollments — exactly the ones a
  /// sub-collection creates.
  Future<Set<String>?> advertisedBy(String owner, String namespace) async {
    Set<String>? agreed;
    for (final level in NskeyResolver.candidates(namespace)) {
      final capability = await _at(owner, level);
      if (capability == null) continue;
      agreed = agreed == null
          ? capability.schemes
          : agreed.intersection(capability.schemes);
    }
    return agreed;
  }

  /// The marker published at exactly [namespace], with no walk.
  Future<FleetCapability?> _at(String owner, String namespace) async {
    final scope = _scope(owner, namespace);
    final cached = _fetched[scope];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < ttl) {
      return cached.capability;
    }

    final String payload;
    try {
      final value =
          await _atClient.get(capabilityAdvertisementKey(owner, namespace));
      if (value.value == null) return _record(scope, null);
      payload = value.value as String;
    } catch (e) {
      // **Absent and unreachable are different answers**, and this is the one
      // place they can still be told apart. A fleet that has never run an
      // upgraded client has published nothing, and that is a durable fact worth
      // remembering — re-asking on every write would put a round trip to
      // someone else's atServer on the write path. An atServer that could not
      // be reached has told us nothing at all, so the last answer stands until
      // the grace runs out.
      if (e is KeyNotFoundException || e is AtKeyNotFoundException) {
        return _record(scope, null);
      }
      return _staleOrNothing(scope, cached);
    }

    try {
      return _record(scope, await verifier.verify(owner, payload));
    } catch (e) {
      // A marker that cannot be verified is worse than no marker: it is what a
      // downgrade attack looks like. Refuse it — but remember the refusal as
      // "no evidence" for the usual window, or an unverifiable marker sitting
      // on a peer's atServer would put a fresh round trip on every write this
      // client ever makes to it.
      _logger.warning('Ignoring the capability marker for $owner:$namespace — '
          'it is present but could not be verified as theirs: $e');
      return _record(scope, null);
    }
  }

  FleetCapability? _record(String scope, FleetCapability? capability) {
    _fetched[scope] = (capability: capability, fetchedAt: DateTime.now());
    return capability;
  }

  FleetCapability? _staleOrNothing(String scope,
      ({FleetCapability? capability, DateTime fetchedAt})? cached) {
    if (cached == null) return null;
    if (DateTime.now().difference(cached.fetchedAt) <= ttl + staleGrace) {
      return cached.capability;
    }
    _fetched.remove(scope);
    return null;
  }

  /// Publish this atSign's marker for [namespace], stating that every
  /// enrollment of it can read [schemes].
  ///
  /// Written straight to the atServer first, then locally: a marker is only
  /// useful once a *peer* can fetch it, and a local-first write would leave it
  /// unpublished until the next sync — during which senders would keep
  /// negotiating against the answer it replaces.
  Future<void> publish(
      {required String namespace, required Set<String> schemes}) async {
    final owner = _atClient.getCurrentAtSign();
    if (owner == null) {
      throw StateError('a capability marker can only be published by a client '
          'that knows its own atSign');
    }

    await _signer.publishPublicSigningKey();
    final payload = await _signer.wrapAndSignAndJsonEncode({
      'schemes': schemes.toList()..sort(),
      'declaredAt': DateTime.now().toUtc().toIso8601String(),
    });

    final markerKey = capabilityAdvertisementKey(owner, namespace);
    await _atClient.getRemoteSecondary()!.executeVerb(
        UpdateVerbBuilder()
          ..atKey = markerKey
          ..value = payload,
        sync: true);
    await _atClient.put(markerKey, payload);

    // This client's own view of its atSign is now stale by construction.
    _fetched.remove(_scope(owner, namespace));
    _logger.info('Published the capability marker for $owner:$namespace: '
        '${schemes.join(', ')}');
  }
}
