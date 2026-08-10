import 'dart:async';

import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/conveyed_key_collection.dart'
    show collectConveyedKeyMaterial;
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart'
    show NskeyPrivateFiling;
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart'
    show NskeySeeding;
import 'package:at_client/src/crypto/nskey/pq_signing_chain.dart'
    show PqSigningChain;
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart'
    show PqSigningRoot;
import 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart'
    show PublishedNskeyKeyRing;
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// Gates for the PQ startup's ACTIVE steps — the ones that write to the
/// atServer on the client's own initiative.
///
/// Every default is on: this object is the *seam* for the passive-by-default
/// posture surveyed in `docs/projects/pq/implementation-plan.md` 14.13,
/// not the posture itself — flipping defaults is a later, deliberate rollout
/// decision. The two read-precondition steps (hydrating held secrets and
/// collecting conveyed key material) deliberately have no gate here:
/// gating them breaks *decryption*, not quietens writes — the collect sweep
/// is the only route by which a conveyed nskey private reaches the keyfile.
///
/// Two of 14.13's active sites live outside the startup and are not gated
/// by this object: `KeyPackageRegistration.register()`'s
/// `publishPublicSigningKey`, and namespace-key seeding, which keeps its
/// own `AtClientPreference.seedNamespaceKeys` knob.
@experimental
class PqStartupGates {
  const PqStartupGates({
    this.requestRootPrivate = true,
    this.requestMissingPrivates = true,
    this.publishRootLink = true,
    this.publishChainLink = true,
    this.sweepUnanchoredEnrollments = true,
    this.askOnReadMiss = true,
  });

  /// Active: broadcasts an ask for the signing-root private.
  final bool requestRootPrivate;

  /// Active: broadcasts asks for nskey privates this enrollment lacks.
  final bool requestMissingPrivates;

  /// Active: publishes this enrollment's self-signed root link.
  final bool publishRootLink;

  /// Active: publishes the approval-chain link this enrollment was given.
  final bool publishChainLink;

  /// Active: a fully privileged client signs and conveys links for
  /// approved enrollments that lack one.
  final bool sweepUnanchoredEnrollments;

  /// Active: the read path's self-heal — a miss on an own generation
  /// broadcasts a pull. Off means the key ring is built without the
  /// conveyance-request hook.
  final bool askOnReadMiss;
}

/// One PQ startup per client — the single owner of the nskey key ring,
/// private filing, secret sharing and signing-root instances that the
/// startup steps and the client's crypto config share.
///
/// Before this existed, `AtClientImpl` built a fresh
/// [PublishedNskeyKeyRing] (and filing, and sharing, and root) inside each
/// startup action — five ring constructions per client — so a private held
/// in one instance's memory was invisible to the next, and the era crypto
/// config read through yet another. Everything now reads and writes the
/// same instances, and a client's whole PQ startup is one ordered task
/// instead of two racing unawaited ones.
///
/// The steps run in a fixed order, each failing independently (logged,
/// never thrown — a client's startup must not fail because of a rollout
/// action; whatever a step missed is retried at the next start):
///
///  1. hydrate held secrets   — read-precondition: primes the in-memory
///     store this client ANSWERS other enrollments' pulls from. Must
///     precede anything that sweeps, because the sweep consumes and
///     deletes the requests it finds.
///  2. collect conveyed keys  — read-precondition: the only route by which
///     key material conveyed by other enrollments reaches the keyfile.
///  3. seed namespace keys    — active, gated by
///     `AtClientPreference.seedNamespaceKeys`: mints and publishes this
///     atSign's namespace keys and conveys each private.
///  4. request root private   — active: asks holders for the signing-root
///     private this enrollment should have and does not.
///  5. request missing privates — active: the pull half of the self-heal
///     invariant (decisions.md 38).
///  6. publish root link      — active: anchor directly to the root when
///     this enrollment can; the better outcome of the two link kinds.
///  7. publish chain link     — active: fall back to the approval-chain
///     link this enrollment was given.
///  8. sweep unanchored       — active, privilege-gated: a fully
///     privileged client signs and conveys links for approved enrollments
///     that lack one.
///
/// [startupComplete] completes when the last step has run; `_init` fires
/// [startup] unawaited and must never await it.
@experimental
class PqClientBootstrap {
  PqClientBootstrap(
    this._atClient, {
    required AtKeysIo? keysIo,
    required EnrollmentPrivilegeResolver privilege,
    required Future<int> Function() sweepUnanchoredEnrollments,
    PqStartupGates gates = const PqStartupGates(),
  })  : _keysIo = keysIo,
        _privilege = privilege,
        _sweepUnanchored = sweepUnanchoredEnrollments,
        _gates = gates {
    _logger = AtSignLogger('PqClientBootstrap ($_atSign'
        '${_atClient.enrollmentId == null ? '' : ', ${_atClient.enrollmentId}'})');
    filing = keysIo == null
        ? null
        : NskeyPrivateFiling(keysIo: keysIo, atSign: _atSign);
    sharing = AtClientSecretSharing.forClient(_atClient);
    ring = PublishedNskeyKeyRing(
      _atClient,
      privateFiling: filing,
      // The read path's self-heal (decisions.md 38): a miss on an own
      // generation broadcasts a pull, so a record that arrived before its
      // key stops being permanently unreadable and becomes merely early.
      // Only when the answer has somewhere durable to land.
      requestConveyance: (keysIo == null || !gates.askOnReadMiss)
          ? null
          : (namespace, secretName) =>
              sharing.requestSecretsFromNamespace(namespace,
                  names: [secretName]),
    );
    seeding = NskeySeeding(
      atClient: _atClient,
      ring: ring,
      privateFiling: filing,
      sharing: sharing,
    );
    root = PqSigningRoot(_atClient, keysIo: keysIo);
  }

  final AtClient _atClient;
  final AtKeysIo? _keysIo;
  final EnrollmentPrivilegeResolver _privilege;
  final Future<int> Function() _sweepUnanchored;
  final PqStartupGates _gates;
  late final AtSignLogger _logger;

  /// The one key ring this client's crypto config and startup steps share.
  late final PublishedNskeyKeyRing ring;

  /// The one durable-filing instance behind [ring] and [seeding], or null
  /// when the client has no `AtKeysIo`.
  late final NskeyPrivateFiling? filing;

  /// The client's shared secret-sharing composition
  /// ([AtClientSecretSharing.forClient]).
  late final AtClientSecretSharing sharing;

  /// Minting, conveyance and the pull half of the self-heal invariant,
  /// all against [ring] and [filing].
  late final NskeySeeding seeding;

  /// This client's view of the atSign's signing root.
  late final PqSigningRoot root;

  String get _atSign => _atClient.getCurrentAtSign()!;

  final Completer<void> _startupComplete = Completer<void>();
  bool _started = false;

  /// Completes when the last startup step has run. Steps fail
  /// independently and are logged, so this never completes with an error —
  /// it answers "has the startup finished?", not "did every step work?".
  Future<void> get startupComplete => _startupComplete.future;

  bool _stopped = false;

  /// Halts the startup at the next step boundary. A step already running
  /// finishes — steps are atomic — but no further step starts, so a
  /// stopped client stops publishing. Idempotent; [startupComplete] still
  /// completes.
  void stop() {
    _stopped = true;
  }

  /// Runs the ordered steps. Fired unawaited by the client's init;
  /// idempotent — a second call returns [startupComplete] without
  /// re-running anything.
  Future<void> startup() async {
    if (_started) return startupComplete;
    _started = true;
    try {
      for (final step in [
        _hydrateHeldSecrets,
        _collectConveyedKeys,
        _seedNamespaceKeys,
        _requestRootPrivate,
        _requestMissingPrivates,
        _publishRootLink,
        _publishChainLink,
        _sweepUnanchoredEnrollments,
      ]) {
        if (_stopped) {
          _logger.info('PQ startup stopped for $_atSign; the remaining '
              'steps will not run (the next start retries them)');
          break;
        }
        await step();
      }
    } finally {
      _startupComplete.complete();
    }
  }

  /// Primes the in-memory secret store with the key material this client
  /// holds durably, so it can **answer** other enrollments' pull requests.
  ///
  /// Must run before anything sweeps: a sweep consumes and deletes the
  /// requests it finds and answers them from this store, so a holder that
  /// hydrates afterwards destroys exactly the requests it was supposed to
  /// serve. The store is in-memory by design and a restart empties it, which
  /// is why this is a re-prime on every start rather than a one-off.
  Future<void> _hydrateHeldSecrets() async {
    final keysIo = _keysIo;
    if (keysIo == null) return;
    try {
      await seeding.hydrateStoreFromFiling(sharing);

      // The signing root, which is atSign-level and so has no namespace of
      // its own: it is offered under the client's namespace, because that is
      // where requesters ask. Cheap check first — holding nothing settles it
      // without the round trip that resolving privilege costs, and that is
      // every client but the rare privileged one.
      final askIn = _atClient.getPreferences()?.namespace;
      if (askIn == null || askIn.isEmpty) return;
      if (await root.privateHalf(_atSign) == null) return;

      // Before offering it, check it is the right key. A private that
      // corresponds to nothing published — the residue of a create this
      // client lost, or of a crash — otherwise blocks its own repair
      // forever: it satisfies the pull's "already holding it" guard, so this
      // enrollment never asks, and it would be served to enrollments that
      // asked, spending their broadcast on bytes their own check then
      // rejects. This is the "a later start reconciles it" the mint's severe
      // log promises, and it is promised HERE because a mint is once per
      // keyfile while a start is every time.
      if (await root.reconcileHeldPrivate(_atSign)) return;

      // A scoped enrollment should not be holding this at all; one that
      // somehow does must not go on to offer it to others.
      if (!await _privilege.isFullyPrivileged()) return;
      await root.hydrateStore(sharing, askIn);
    } catch (e, st) {
      _logger.warning('Could not prime what $_atSign holds for answering '
          'other enrollments; their pulls go unanswered until the next '
          'start retries: $e, $st');
    }
  }

  /// Files the key material conveyed to this enrollment. The only route by
  /// which a conveyed nskey private reaches the keyfile — a
  /// read-precondition, never gated.
  Future<void> _collectConveyedKeys() async {
    final keysIo = _keysIo;
    if (keysIo == null) return;
    try {
      await collectConveyedKeyMaterial(_atClient, keysIo);
    } catch (e, st) {
      _logger.warning('Collecting conveyed key material failed for $_atSign; '
          'this enrollment holds only what it already had, and the next '
          'start retries: $e, $st');
    }
  }

  /// Mints and publishes namespace keys for this client's authorised
  /// namespaces, per `AtClientPreference.seedNamespaceKeys`.
  Future<void> _seedNamespaceKeys() async {
    if (_atClient.getPreferences()?.seedNamespaceKeys != true) return;
    try {
      await seeding.seed();
    } catch (e, st) {
      _logger.warning('Seeding namespace keys failed for $_atSign; the next '
          'start retries whatever is still missing: $e, $st');
    }
  }

  /// Asks for the root private if this enrollment should have one and does
  /// not — an enrollment that was offline when it was approved has no other
  /// way to get it, since the root carries no namespace and so never rides
  /// the enroll:listns fan-out. The call broadcasts and returns; the answer
  /// is filed by the collection step at this or a later start.
  ///
  /// Placed before anchoring rather than after because anchoring needs the
  /// private, so on the rare start where an answer is already waiting, both
  /// succeed in one pass.
  Future<void> _requestRootPrivate() async {
    if (!_gates.requestRootPrivate) return;
    try {
      // The request rides the client's own namespace, because that is where
      // its key package is registered and so where holders can be
      // enumerated. A client with no namespace has nowhere to ask and is
      // skipped rather than force-unwrapped — this runs on every start, and
      // a null here would turn a missing preference into a failed client
      // construction.
      final askIn = _atClient.getPreferences()?.namespace;
      if (askIn == null || askIn.isEmpty) return;
      await root.requestPrivateIfAbsent(
        isFullyPrivileged: _privilege.isFullyPrivileged,
        sharing: sharing,
        namespace: askIn,
      );
    } catch (e, st) {
      _logger.warning('Could not ask for the signing root private for '
          '$_atSign; this enrollment stays unanchored and the next start '
          'retries: $e, $st');
    }
  }

  /// Asks for any nskey privates this enrollment is entitled to and does
  /// not hold — the pull half of the self-heal invariant (decisions.md 38).
  /// An enrollment created after a namespace was minted missed the
  /// mint-time push, and this is its route to the key; without it the
  /// namespace reads as one this client can never open. Guarded on the
  /// keysIo because the answer must have somewhere durable to land.
  Future<void> _requestMissingPrivates() async {
    if (!_gates.requestMissingPrivates) return;
    if (_keysIo == null) return;
    try {
      // The supply side already ran, before the sweep that answers with it
      // (see _hydrateHeldSecrets).
      final asked = await seeding.requestMissingPrivates(sharing);
      if (asked.isNotEmpty) {
        _logger.info('Asked other enrollments for the nskey private(s) of '
            '${asked.join(', ')}; answers are filed as they arrive');
      }
    } catch (e, st) {
      _logger.warning('Could not request missing nskey privates for '
          '$_atSign; the affected namespaces stay unreadable until the next '
          'start retries: $e, $st');
    }
  }

  /// Anchoring is attempted before the chain link because it is the better
  /// outcome of the two: an enrollment that can reach the root directly has
  /// no need of a hop through whoever approved it.
  Future<void> _publishRootLink() async {
    if (!_gates.publishRootLink) return;
    try {
      await PqSigningChain.publishOwnRootLink(_atClient,
          isFullyPrivileged: _privilege.isFullyPrivileged, keysIo: _keysIo);
    } catch (e, st) {
      _logger.warning('Anchoring $_atSign to its signing root failed; the '
          'enrollment falls back to its approval-chain link and the next '
          'start retries: $e, $st');
    }
  }

  Future<void> _publishChainLink() async {
    if (!_gates.publishChainLink) return;
    try {
      await PqSigningChain.publishPendingLink(_atClient);
    } catch (e, st) {
      _logger.warning('Publishing the approval-chain link failed for '
          '$_atSign; the enrollment stays unsigned, which verifiers '
          'tolerate, and the next start retries: $e, $st');
    }
  }

  /// The chain sweep (decisions.md 38, decision 3): a fully privileged
  /// client signs and conveys links for approved enrollments that lack
  /// one. A scoped enrollment cannot anchor itself and its approver may be
  /// a legacy enrollment that can sign nothing, so without this sweep
  /// chained-but-unanchored is a permanent state rather than a transient.
  /// Gated on privilege here rather than inside, because a link signed by
  /// an unanchored sweeper adds a hop without reaching the root.
  Future<void> _sweepUnanchoredEnrollments() async {
    if (!_gates.sweepUnanchoredEnrollments) return;
    try {
      if (await _privilege.isFullyPrivileged()) {
        await _sweepUnanchored();
      }
    } catch (e, st) {
      _logger.warning('The chain sweep failed for $_atSign; unanchored '
          'enrollments stay unanchored, which verifiers tolerate, and the '
          'next privileged start retries: $e, $st');
    }
  }

  /// The step names in run order, for tests that pin the ordering contract.
  @visibleForTesting
  static const List<String> stepNamesInOrder = [
    'hydrateHeldSecrets',
    'collectConveyedKeys',
    'seedNamespaceKeys',
    'requestRootPrivate',
    'requestMissingPrivates',
    'publishRootLink',
    'publishChainLink',
    'sweepUnanchoredEnrollments',
  ];
}
