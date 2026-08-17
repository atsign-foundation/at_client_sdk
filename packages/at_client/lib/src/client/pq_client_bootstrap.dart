import 'dart:async';

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysEnrollment, AtKeysIo, WrittenAtKeysIo;
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
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_commons/atsign.dart' show AtsignString;
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
    this.mintInUseSigningKeys = true,
    this.requestRootPrivate = true,
    this.requestMissingPrivates = true,
    this.publishRootLink = true,
    this.publishChainLink = true,
    this.sweepUnanchoredEnrollments = true,
    this.askOnReadMiss = true,
  });

  /// Active: brings this enrollment's signing keys into line with
  /// `AtClientPreference.inUseSigningAlgorithms` — minting, advertising and
  /// filing one for every algorithm the set names and the enrollment does not
  /// hold, and retiring every one it holds that the set no longer names.
  /// Inert while that set is empty, which is the 3.x default, so this gate
  /// governs the 4.0 posture and an app that opts in early.
  final bool mintInUseSigningKeys;

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
///  3. mint in-use signing keys — active: gives this enrollment a signing key
///     of its own for every algorithm the in-use set names, and retires the
///     ones it no longer names. Before every step that signs, so that anything
///     published later in this same startup is signed by the keys the
///     advertisement now names, and by none it has withdrawn.
///  4. seed namespace keys    — active, gated by
///     `AtClientPreference.seedNamespaceKeys`: mints and publishes this
///     atSign's namespace keys and conveys each private.
///  5. request root private   — active: asks holders for the signing-root
///     private this enrollment should have and does not.
///  6. request missing privates — active: the pull half of the self-heal
///     invariant (decisions.md 38).
///  7. publish root link      — active: anchor directly to the root when
///     this enrollment can; the better outcome of the two link kinds.
///  8. publish chain link     — active: fall back to the approval-chain
///     link this enrollment was given.
///  9. sweep unanchored       — active, privilege-gated: a fully
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
    // The substrate's per-enrollment secret request gate consults the same
    // injected privilege seam as the startup steps — wired here, in the
    // ctor, because a request can arrive as soon as the client listens,
    // not only after the startup steps have run. Without it the gate is
    // null and the substrate fails closed.
    sharing.perEnrollmentSecretRequestGate =
        (requesterEnrollmentId) =>
            _privilege.isEnrollmentFullyPrivileged(requesterEnrollmentId);
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
    chain = PqSigningChain(_atClient);
    minting = SigningKeyMinting(_atClient);
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

  /// This client's view of the approval chain.
  late final PqSigningChain chain;

  /// Gives this enrollment its own signing keys, per the in-use set.
  late final SigningKeyMinting minting;

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
        _mintInUseSigningKeys,
        _seedNamespaceKeys,
        _requestRootPrivate,
        _requestMissingPrivates,
        _publishRootLink,
        _publishChainLink,
        _sweepUnanchoredEnrollments,
        _reconcileEnrollmentSnapshot,
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
      // `ring:` so the sweep files through THIS client's one filing rather
      // than building a second. Two filings wrote the same keyfile and looked
      // equivalent until a filing gained an observable event: the one emitting
      // it was then not the one the ring exposes, so nothing could hear it.
      await collectConveyedKeyMaterial(_atClient, keysIo, ring: ring);
    } catch (e, st) {
      _logger.warning('Collecting conveyed key material failed for $_atSign; '
          'this enrollment holds only what it already had, and the next '
          'start retries: $e, $st');
    }
  }

  /// Mints, advertises and files a signing key for every algorithm the in-use
  /// set names and this enrollment does not hold, and retires every one it
  /// holds that the set no longer names.
  ///
  /// Runs before every step that signs — the namespace-key seeding, both link
  /// publications and the sweep all produce signed envelopes — so a key minted
  /// on this start is already advertised by the time anything signs with it,
  /// and a key retired on this start signs nothing more. Running it after them
  /// would leave one start's envelopes signed by a key the advertisement of
  /// that moment did not name, and one start's worth signed by a key that has
  /// left service.
  Future<void> _mintInUseSigningKeys() async {
    if (!_gates.mintInUseSigningKeys) return;
    try {
      await minting.reconcileSigningKeys();
    } catch (e, st) {
      _logger.warning('Minting this enrollment\'s own signing keys failed for '
          '$_atSign; it keeps signing with the key it already advertises, and '
          'the next start retries: $e, $st');
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
      await chain.publishOwnRootLink(
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
      await chain.publishPendingLink();
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

  /// Records what the atServer's enrollment record says about this
  /// enrollment — its `namespaces`, `appName` and `deviceName` — on the
  /// keyfile.
  ///
  /// An enrollment created from an `enroll:request` carries all three from
  /// birth, because the writer held the request. A retrofit, or an onboard
  /// handed its keys by the caller, has no request and omits them, and this
  /// is where those files get them. It runs on **every** start rather than
  /// once, because a grant can change after the file was written — the
  /// keyfile's copy would otherwise keep describing an enrollment the
  /// atServer has since re-scoped.
  ///
  /// Last in the order deliberately: nothing else reads the snapshot, so it
  /// can only delay steps that heal key material, never enable one.
  ///
  /// ⚠️ **Only for an enrollment the keyfile already holds.** Recording a
  /// snapshot *creates* the slot when it is missing, and an enrollment slot
  /// is typed content ([AtKeys.toJson] treats a non-empty `enrollments` as
  /// exactly that) — so doing this for an enrollment with no material would
  /// rewrite a legacy-flat keyfile as a version 1 document purely as a side
  /// effect of having opened it. Filling in a snapshot is this step's job;
  /// converting a keyfile is not.
  ///
  /// Through [WrittenAtKeysIo.update], the store's atomic verb, because this
  /// is a start-time writer on the one file that several start-time writers
  /// share: a hand-rolled read → mutate → flush loses whichever flushes
  /// second, and this tree has lost key material exactly that way.
  Future<void> _reconcileEnrollmentSnapshot() async {
    final keysIo = _keysIo;
    if (keysIo is! WrittenAtKeysIo) return;

    // No enrollment id means this client authenticates with the atSign's own
    // keys. There is no enrollment record to read, and `enroll:fetch` would
    // be answered for whatever id it was handed rather than refused.
    final enrollmentId = _atClient.enrollmentId;
    if (enrollmentId == null) return;

    try {
      // Shared with the authorization path rather than fetched again: one
      // record described by two readers is two chances to disagree about it.
      final record =
          await _atClient.getLocalSecondary()?.getEnrollmentDetails();
      if (record == null) return;

      final namespaces = _namespaceGrantsOf(record.namespace);
      await keysIo.update(_atSign.toAtsign(), (keys) {
        if (!keys.enrollmentIds.contains(enrollmentId)) {
          _logger.finer('Not recording an enrollment snapshot for '
              '$enrollmentId: this keyfile holds no material for it, and '
              'creating a slot would make a legacy file a typed one');
          return false;
        }
        final held = keys.enrollmentInfo(enrollmentId);
        if (_snapshotAgrees(held, namespaces, record.appName,
            record.deviceName)) {
          return false;
        }
        // A grant change is something the user may care about, so it is said
        // out loud — but only when there was a previous value to differ from.
        // The first reconciliation of a retrofit's keyfile is a fill, not a
        // change, and logging it as one would cry wolf on every such file.
        if (held?.namespaces != null &&
            namespaces != null &&
            !_sameGrants(held!.namespaces!, namespaces)) {
          _logger.warning(
              'The grants on enrollment $enrollmentId have changed: this '
              'keyfile recorded ${held.namespaces}, and the atServer now '
              'says $namespaces');
        }
        keys.recordEnrollmentSnapshot(
          enrollmentId,
          namespaces: namespaces,
          appName: record.appName,
          deviceName: record.deviceName,
        );
        return true;
      });
    } catch (e, st) {
      _logger.warning('Could not reconcile the enrollment snapshot for '
          '$_atSign; the keyfile keeps whatever it already recorded and the '
          'next start retries: $e, $st');
    }
  }

  /// The enrollment record's namespace grants as the keyfile stores them.
  ///
  /// The wire field is `Map<String, dynamic>` and the atServer fills it from
  /// its own `Map<String, String>`, so every value should already be a
  /// string. An entry whose value is not one is **skipped rather than
  /// stringified**: `'null'` or `'{}'` recorded as an access level reads as a
  /// grant, and a missing entry reads as what it is.
  static Map<String, String>? _namespaceGrantsOf(Map<String, dynamic>? wire) {
    if (wire == null) return null;
    return {
      for (final entry in wire.entries)
        if (entry.value is String) entry.key: entry.value as String
    };
  }

  static bool _snapshotAgrees(AtKeysEnrollment? held,
      Map<String, String>? namespaces, String? appName, String? deviceName) {
    if (held == null) return false;
    // A null incoming field leaves the held one alone, so it cannot disagree.
    if (appName != null && held.appName != appName) return false;
    if (deviceName != null && held.deviceName != deviceName) return false;
    if (namespaces != null &&
        (held.namespaces == null || !_sameGrants(held.namespaces!, namespaces))) {
      return false;
    }
    return true;
  }

  static bool _sameGrants(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// The step names in run order, for tests that pin the ordering contract.
  @visibleForTesting
  static const List<String> stepNamesInOrder = [
    'hydrateHeldSecrets',
    'collectConveyedKeys',
    'mintInUseSigningKeys',
    'seedNamespaceKeys',
    'requestRootPrivate',
    'requestMissingPrivates',
    'publishRootLink',
    'publishChainLink',
    'sweepUnanchoredEnrollments',
    'reconcileEnrollmentSnapshot',
  ];
}
