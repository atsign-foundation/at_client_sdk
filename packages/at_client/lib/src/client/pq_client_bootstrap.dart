import 'dart:async';

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysEnrollment, AtKeysIo, WrittenAtKeysIo;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/crypto.dart' show CryptoConfig;
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
    show PublishedNskeyKeyRing, requestAndFileNskeyPrivate;
import 'package:at_client/src/enroll/privilege_resolver.dart';
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/key_package_minting.dart'
    show KeyPackageMinting;
import 'package:at_client/src/signing/signing_key_mint_barrier.dart'
    show registerSigningKeyMintBarrier;
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// Gates for the PQ startup's ACTIVE steps — the ones that write to the
/// atServer on the client's own initiative.
///
/// Every default is on, and the posture turns two of them off. `AtClientImpl`
/// passes [reconcileKeyPackage] and [requestMissingPrivates] as false when
/// `PqPosture.configuresPqProviders` is false, so a stage standing in for a
/// build that predates the post-quantum providers neither advertises a key
/// package nor asks for privates it has no provider to use. Every other
/// default is still on for every stage.
///
/// The two read-precondition steps (hydrating held secrets and collecting
/// conveyed key material) deliberately have no gate here: gating them breaks
/// *decryption*, not quietens writes — the collect sweep is the only route by
/// which a conveyed nskey private reaches the keyfile. A client that cannot
/// resolve the providers fails before it needs one either way, so leaving them
/// on costs it nothing and keeps the sweep available the moment a posture that
/// does configure them is adopted.
///
/// Two of 14.13's active sites live outside the startup and are not gated
/// by this object: `KeyPackageRegistration.register()`'s
/// `publishPublicSigningKey`, and namespace-key seeding, which keeps its
/// own `AtClientPreference.seedNamespaceKeys` knob.
@experimental
class PqStartupGates {
  const PqStartupGates({
    this.mintInUseSigningKeys = true,
    this.reconcileKeyPackage = true,
    this.requestRootPrivate = true,
    this.requestMissingPrivates = true,
    this.publishRootLink = true,
    this.publishChainLink = true,
    this.sweepUnanchoredEnrollments = true,
    this.askOnReadMiss = true,
  });

  /// Active: brings this enrollment's signing keys into line with
  /// `AtClientPreference.dataSigningKeyAlgorithms` — minting, advertising and
  /// filing one for every algorithm the set names and the enrollment does not
  /// hold, and retiring every one it holds that the set no longer names.
  /// Inert while that set is empty, which is the 3.x default, so this gate
  /// governs the 4.0 posture and an app that opts in early.
  final bool mintInUseSigningKeys;

  /// Active: brings this enrollment's advertised key package into line with
  /// `AtClientPreference.keyEstablishmentAlgorithms` — minting, filing and
  /// advertising an encapsulation keypair for every algorithm the list names
  /// and the enrollment does not hold, and retiring every one it holds that
  /// the list no longer names. Inert unless that list has changed since the
  /// enrollment was created, which is every start after the first.
  final bool reconcileKeyPackage;

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
///     invariant.
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
    sharing.perEnrollmentSecretRequestGate = (requesterEnrollmentId) =>
        _privilege.isEnrollmentFullyPrivileged(requesterEnrollmentId);
    ring = PublishedNskeyKeyRing(
      _atClient,
      privateFiling: filing,
      // The read path's self-heal: a miss on an own
      // generation broadcasts a pull, so a record that arrived before its
      // key stops being permanently unreadable and becomes merely early.
      // Only when the answer has somewhere durable to land.
      // ⚠️ The ask alone is not the heal. Asking puts the answer in the
      // in-memory secret store, and **nothing files it from there
      // mid-session**: `NskeyPrivateFiling.filePending` runs at start and says
      // so itself ("a private that arrives after this runs is filed at the next
      // start"). So a read-miss heal that only broadcast would repair the
      // client at its *next* start, not this one — measured live 2026-08-17,
      // with the holder replying correctly and the answer sitting unfiled.
      //
      // The startup path already waits and files (`NskeySeeding`); this does
      // the same, so the two agree.
      //
      // The body is `requestAndFileNskeyPrivate`, shared with the default the
      // ring builds for itself when nobody supplies one — the same wait, the
      // same filing, the same logging, so a client that reached the ring
      // through the bootstrap and one that did not heal identically. What is
      // passed here rather than derived is the GATE: only the bootstrap knows
      // `askOnReadMiss`, and a ring given null asks nothing.
      requestConveyance: (keysIo == null || !gates.askOnReadMiss)
          ? null
          : (namespace, secretName) => requestAndFileNskeyPrivate(
              sharing, filing, namespace, secretName,
              logger: _logger),
    );
    seeding = NskeySeeding(
      atClient: _atClient,
      ring: ring,
      privateFiling: filing,
      sharing: sharing,
      // Resolved at the moment the question is asked, not here. This runs
      // during client construction, and an application that assigns
      // `preference.crypto` afterwards — which is the ordinary way to choose a
      // configuration — would otherwise have its policy read before it set one.
      rotationPolicy: (ns) =>
          CryptoConfig.forClient(_atClient).nskeyRotationPolicy(ns),
    );
    root = PqSigningRoot(_atClient, keysIo: keysIo);
    chain = PqSigningChain(_atClient);
    minting = SigningKeyMinting(_atClient);
    keyPackageMinting = KeyPackageMinting(_atClient);
    // Registered in the constructor rather than at startup so a signer that
    // runs before startup() is fired still waits: the window it closes opens
    // the moment minting becomes possible, not the moment it begins.
    registerSigningKeyMintBarrier(_atClient, mintSettled);
  }

  final AtClient _atClient;
  final AtKeysIo? _keysIo;
  final EnrollmentPrivilegeResolver _privilege;
  final Future<int> Function() _sweepUnanchored;
  final PqStartupGates _gates;

  /// The gates this startup is running under.
  ///
  /// Exposed because which steps a posture switches off is a contract a test
  /// has to be able to read: the alternative is asserting on the absence of a
  /// wire write, which passes just as well when the step ran and failed.
  @visibleForTesting
  PqStartupGates get gates => _gates;
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

  /// Keeps this enrollment's advertised key package in line with the
  /// configured key-establishment algorithms.
  late final KeyPackageMinting keyPackageMinting;

  String get _atSign => _atClient.getCurrentAtSign()!;

  final Completer<void> _startupComplete = Completer<void>();
  bool _started = false;

  /// Completes when the last startup step has run. Steps fail
  /// independently and are logged, so this never completes with an error —
  /// it answers "has the startup finished?", not "did every step work?".
  Future<void> get startupComplete => _startupComplete.future;

  final Completer<void> _mintSettled = Completer<void>();

  /// Completes when the signing-key mint step has run — or will not run this
  /// session, because the startup was stopped or failed before reaching it or
  /// the step is gated off. Never completes with an error.
  ///
  /// This is what a signer waits on before reading which keys may sign
  /// ([registerSigningKeyMintBarrier] hands it over in the constructor):
  /// publishing a minted key withdraws the authentication fallback from the
  /// advertisement before the keyfile holds the minted one, so a sign in that
  /// window produces an envelope nothing can verify. Waiting on
  /// [startupComplete] instead would deadlock — the steps after the mint sign
  /// envelopes themselves.
  Future<void> get mintSettled => _mintSettled.future;

  bool _stopped = false;

  /// Halts the startup at the next step boundary. A step already running
  /// finishes — steps are atomic — but no further step starts, so a
  /// stopped client stops publishing. Idempotent; [startupComplete] still
  /// completes.
  void stop() {
    _stopped = true;
    // Paired with [_startEnvelopeListener]. Without this a stopped client keeps
    // a periodic timer, a sync listener and a notification subscription alive
    // for the life of the process.
    sharing.stopListening();
  }

  /// Runs the ordered steps. Fired unawaited by the client's init;
  /// idempotent — a second call returns [startupComplete] without
  /// re-running anything.
  Future<void> startup() async {
    if (_started) return startupComplete;
    _started = true;

    // Hand the content-key manager the one thing it cannot build for itself:
    // replacing a namespace key needs the substrate that conveys the successor
    // to every authorised enrollment, and the manager holds only what it needs
    // to seal. Assigned here rather than in the constructor because the
    // configuration is resolved per client and an application that names one
    // does so after construction.
    CryptoConfig.forClient(_atClient).ckManager?.rotateOwnNamespaceKeyIfAsked =
        (namespace) => seeding.rotateIfPolicyAsks(
            _atClient.getCurrentAtSign()!, namespace);

    final steps = _steps;
    try {
      for (var i = 0; i < steps.length; i++) {
        if (_stopped) {
          _warnAbandoned(steps.sublist(i).map((step) => step.name).toList());
          break;
        }
        await steps[i].run();
      }
    } finally {
      // A startup that stopped or failed before the mint step still settles
      // the barrier: everything that signs waits on it, and those signers
      // should sign with what the keyfile holds today rather than wait for a
      // mint that is not coming this session.
      if (!_mintSettled.isCompleted) _mintSettled.complete();
      _startupComplete.complete();
    }
  }

  /// Says what a stopped startup did not do, at **warning**.
  ///
  /// `warning` rather than `info` because the cost of an abandoned tail is
  /// paid by a *different principal in a different process*: this atSign goes
  /// on sending — sending needs the recipient's key, not its own — while no
  /// peer can seal to it, so the only symptom surfaces at the far end, where
  /// a different atSign reports this one as having no published key. Diagnosed
  /// from that end it names the wrong party, which is where a day went on
  /// 2026-08-26. The same reasoning as an event dropped in a delivery loop:
  /// silence here is indistinguishable from the work never having been needed.
  ///
  /// The skipped steps are named individually because "the remaining steps" is
  /// not something a reader can act on, and which ones were missed decides
  /// what is now untrue about this client.
  ///
  /// ⚠️ **Deliberately does not say "the next start retries them."** It is
  /// true and it reads as reassurance, and the process shape that reaches this
  /// line — a CLI tool, a cron job, a one-shot notifier with piped stdin — is
  /// precisely the one whose next start is just as short-lived. Saying it
  /// invites a reader to stop looking.
  void _warnAbandoned(List<String> skipped) {
    final seedingSkipped = skipped.contains('seedNamespaceKeys') &&
        _atClient.getPreferences()?.seedNamespaceKeys == true;
    _logger.warning(
        'PQ startup for $_atSign was stopped with ${skipped.length} of '
        '${_steps.length} steps still to run, so these did not happen: '
        '${skipped.join(', ')}. A later start runs them again, but a process '
        'that exits this quickly may not have a later start that lives any '
        'longer.'
        '${seedingSkipped ? ' In particular seedNamespaceKeys did not run, so '
            'this atSign may have no published namespace key — it can still '
            'send, and no peer can seal to it.' : ''}');
  }

  /// The ordered startup steps, each with the name [stepNamesInOrder]
  /// reports — one list, so a step cannot run in an order no test can see.
  List<({String name, Future<void> Function() run})> get _steps => [
        (name: 'hydrateHeldSecrets', run: _hydrateHeldSecrets),
        (name: 'collectConveyedKeys', run: _collectConveyedKeys),
        (name: 'startEnvelopeListener', run: _startEnvelopeListener),
        (name: 'mintInUseSigningKeys', run: _mintInUseSigningKeys),
        (name: 'reconcileKeyPackage', run: _reconcileKeyPackage),
        (name: 'seedNamespaceKeys', run: _seedNamespaceKeys),
        (name: 'requestRootPrivate', run: _requestRootPrivate),
        (name: 'requestMissingPrivates', run: _requestMissingPrivates),
        (name: 'publishRootLink', run: _publishRootLink),
        (name: 'publishChainLink', run: _publishChainLink),
        (name: 'sweepUnanchoredEnrollments', run: _sweepUnanchoredEnrollments),
        (
          name: 'reconcileEnrollmentSnapshot',
          run: _reconcileEnrollmentSnapshot
        ),
      ];

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

  /// Keeps sweeping for envelopes addressed to this client, rather than the
  /// single sweep [_collectConveyedKeys] does at start.
  ///
  /// ⚠️ **This is what makes a read-miss self-heal possible at all, and not
  /// only for this client.** `_handleRequestPayload` — the code that answers
  /// another enrollment's request for a secret — is reachable only from
  /// `sweepOnce`. With no listener running, a client's only sweep is the
  /// one-shot at its own start, so a request arriving afterwards is never seen
  /// and never answered. Measured live 2026-08-17: a receiver asked for an
  /// nskey private, the holder never swept again, and the ask went unanswered
  /// for the life of the test.
  ///
  /// Stopped by [stop], which the client's teardown calls.
  Future<void> _startEnvelopeListener() async {
    try {
      await sharing.startListening();
    } catch (e) {
      _logger.warning('Could not start the envelope listener for $_atSign; '
          'this client will not answer other enrollments\' secret requests '
          'and will not pick up envelopes that arrive later: $e');
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
    try {
      if (!_gates.mintInUseSigningKeys) return;
      await minting.reconcileSigningKeys();
    } catch (e, st) {
      _logger.warning('Minting this enrollment\'s own signing keys failed for '
          '$_atSign; it keeps signing with the key it already advertises, and '
          'the next start retries: $e, $st');
    } finally {
      // Success, failure and gated-off all settle the barrier: whatever the
      // keyfile holds after this point is what may sign.
      if (!_mintSettled.isCompleted) _mintSettled.complete();
    }
  }

  /// Brings this enrollment's advertised key package into line with
  /// `AtClientPreference.keyEstablishmentAlgorithms`.
  ///
  /// Runs **after** the signing keys and before anything that publishes,
  /// because the key package is signed by whatever key `_apsk` advertises.
  /// Running it first would sign the package with the key this start is about
  /// to retire, so a peer verifying against the freshly published `_apsk`
  /// would refuse a package that had just been written — and refusing a key
  /// package means refusing to seal anything to this enrollment at all.
  Future<void> _reconcileKeyPackage() async {
    if (!_gates.reconcileKeyPackage) return;
    try {
      await keyPackageMinting.reconcileKeyPackage();
    } catch (e, st) {
      _logger.warning('Reconciling the advertised key package failed for '
          '$_atSign; it goes on answering at the key it already advertises, '
          'and the next start retries: $e, $st');
    }
  }

  /// Mints and publishes namespace keys for this client's authorised
  /// namespaces, per `AtClientPreference.seedNamespaceKeys`.
  ///
  /// **A client with no key source seeds nothing, whatever the posture asks
  /// for.** There would be nowhere to file the private, so the generation
  /// would be published with its private held in memory and nowhere else:
  /// peers seal to the advertised key and every value they seal becomes
  /// unreadable the moment this process ends. `_mint` says so itself, at
  /// `severe`, and declines to refuse there because a fixture may legitimately
  /// mint into memory — which is a decision about an explicit call, not about
  /// a client seeding on its own at startup.
  ///
  /// It also keeps a keyless client inert on the wire. An advertisement or a
  /// signing root written to a real atSign outlives the run that wrote it and
  /// nothing rotates it back out, so a client built to read must not publish
  /// PQ state merely because it named no posture.
  Future<void> _seedNamespaceKeys() async {
    if (_keysIo == null) return;
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
  /// not hold — the pull half of the self-heal invariant.
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

  /// The chain sweep: a fully privileged
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
        if (_snapshotAgrees(
            held, namespaces, record.appName, record.deviceName)) {
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
        (held.namespaces == null ||
            !_sameGrants(held.namespaces!, namespaces))) {
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
  ///
  /// ⚠️ **Derived from [_steps], because a hand-maintained copy had already
  /// drifted.** This was a `static const` list written out by hand beside the
  /// real sequence, and the test pinning "the step order is the documented
  /// one" compared it to a third list written out by hand in the test — so it
  /// compared two transcriptions to each other and never read the sequence
  /// that actually runs. It was missing `startEnvelopeListener` and stayed
  /// green. Order now has one home: the list `startup()` iterates.
  @visibleForTesting
  List<String> get stepNamesInOrder => [for (final step in _steps) step.name];
}
