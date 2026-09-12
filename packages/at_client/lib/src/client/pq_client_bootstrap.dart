import 'dart:async';

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysEnrollment, AtKeysIo, WrittenAtKeysIo;
import 'package:at_client/src/enroll/at_sign_credential.dart';
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
import 'package:at_client/src/util/swallowed_error.dart';
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/key_package_minting.dart'
    show KeyPackageMinting;
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// Gates for the PQ startup's steps — **every** step, not only the ones that
/// write to the atServer.
///
/// Every default is on; [PqStartupGates.inert] turns the whole startup off, so
/// the client makes no wire write, takes no subscription and changes no
/// keyfile.
@experimental
class PqStartupGates {
  /// Every gate is on unless this call names it false.
  const PqStartupGates({
    this.hydrateHeldSecrets = true,
    this.collectConveyedKeys = true,
    this.startEnvelopeListener = true,
    this.mintInUseSigningKeys = true,
    this.reconcileKeyPackage = true,
    this.seedNamespaceKeys = true,
    this.requestRootPrivate = true,
    this.requestMissingPrivates = true,
    this.publishRootLink = true,
    this.publishChainLink = true,
    this.sweepUnanchoredEnrollments = true,
    this.reconcileEnrollmentSnapshot = true,
    this.askOnReadMiss = true,
  });

  /// Every gate off: the startup runs, every step returns at once, and
  /// `startupComplete` completes having done nothing.
  const PqStartupGates.inert()
      : hydrateHeldSecrets = false,
        collectConveyedKeys = false,
        startEnvelopeListener = false,
        mintInUseSigningKeys = false,
        reconcileKeyPackage = false,
        seedNamespaceKeys = false,
        requestRootPrivate = false,
        requestMissingPrivates = false,
        publishRootLink = false,
        publishChainLink = false,
        sweepUnanchoredEnrollments = false,
        reconcileEnrollmentSnapshot = false,
        askOnReadMiss = false;

  /// Read-precondition: primes the in-memory store this client answers other
  /// enrollments' pulls from, and may write a reconciled signing-root private.
  final bool hydrateHeldSecrets;

  /// Read-precondition: files the key material conveyed to this enrollment
  /// into the keyfile. Also the route by which `_apsk` gets published, via
  /// `KeyPackageRegistration.register()`.
  final bool collectConveyedKeys;

  /// Active: the periodic sweep timer, the sync progress listener and the
  /// notification subscription that let envelopes arrive after start.
  final bool startEnvelopeListener;

  /// Active: brings this enrollment's signing keys into line with
  /// `AtClientPreference.dataSigningKeyAlgorithms` — minting, advertising and
  /// filing one for every algorithm the set names and the enrollment does not
  /// hold, and retiring every one it holds that the set no longer names.
  /// Inert while that set is empty.
  final bool mintInUseSigningKeys;

  /// Active: brings this enrollment's advertised key package into line with
  /// `AtClientPreference.keyEstablishmentAlgorithms` — minting, filing and
  /// advertising an encapsulation keypair for every algorithm the list names
  /// and the enrollment does not hold, and retiring every one it holds that
  /// the list no longer names. Inert unless that list has changed since the
  /// enrollment was created, which is every start after the first.
  final bool reconcileKeyPackage;

  /// Active: mints and publishes this atSign's namespace keys. ANDed with
  /// `AtClientPreference.seedNamespaceKeys`, which is the knob an app sets.
  final bool seedNamespaceKeys;

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

  /// Writes the atServer's view of this enrollment's grants onto the keyfile.
  final bool reconcileEnrollmentSnapshot;

  /// Active: the read path's self-heal — a miss on an own generation
  /// broadcasts a pull. Off means the key ring is built without the
  /// conveyance-request hook.
  final bool askOnReadMiss;

  /// The gates that are off, in declaration order, or `every step` when none
  /// are — so a difference between two sets reads as the steps it changes.
  @override
  String toString() {
    final off = [
      for (final gate in _named.entries)
        if (!gate.value) gate.key
    ];
    return off.isEmpty ? 'every step' : 'every step but ${off.join(', ')}';
  }

  /// NOTE: by value, because only `const` instances are canonicalized — a
  /// caller writing `PqStartupGates()` without `const` would otherwise differ
  /// from the default over a difference that does not exist.
  @override
  bool operator ==(Object other) {
    if (other is! PqStartupGates) return false;
    final mine = _named.values.toList();
    final theirs = other._named.values.toList();
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_named.values);

  Map<String, bool> get _named => {
        'hydrateHeldSecrets': hydrateHeldSecrets,
        'collectConveyedKeys': collectConveyedKeys,
        'startEnvelopeListener': startEnvelopeListener,
        'mintInUseSigningKeys': mintInUseSigningKeys,
        'reconcileKeyPackage': reconcileKeyPackage,
        'seedNamespaceKeys': seedNamespaceKeys,
        'requestRootPrivate': requestRootPrivate,
        'requestMissingPrivates': requestMissingPrivates,
        'publishRootLink': publishRootLink,
        'publishChainLink': publishChainLink,
        'sweepUnanchoredEnrollments': sweepUnanchoredEnrollments,
        'reconcileEnrollmentSnapshot': reconcileEnrollmentSnapshot,
        'askOnReadMiss': askOnReadMiss,
      };
}

/// One PQ startup per client — the single owner of the nskey key ring,
/// private filing, secret sharing and signing-root instances that the
/// startup steps and the client's crypto config share.
///
/// The steps run in the fixed order [stepNamesInOrder] reports, each failing
/// independently: a failure is logged rather than thrown, and whatever a step
/// missed is retried at the next start.
///
/// [startupComplete] completes when the last step has run; the client's init
/// fires [startup] unawaited and must never await it.
@experimental
class PqClientBootstrap {
  /// Builds the instances the startup steps share; [gates] decides which of
  /// those steps [startup] then runs.
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
    // NOTE: wired in the constructor rather than in a startup step, because a
    // request can arrive as soon as the client listens. Left null, the gate
    // fails closed.
    sharing.perEnrollmentSecretRequestGate = (requesterEnrollmentId) =>
        _privilege.isEnrollmentFullyPrivileged(requesterEnrollmentId);
    ring = PublishedNskeyKeyRing(
      _atClient,
      privateFiling: filing,
      // NOTE: the read-miss hook must file what it receives, not merely ask.
      // An answer left in the in-memory secret store is not filed again until
      // the next start, so a hook that only broadcast would heal the client
      // one start late.
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
      // NOTE: resolved per call, not captured here — an application assigns
      // `preference.crypto` after the client is constructed.
      rotationPolicy: (ns) =>
          CryptoConfig.forClient(_atClient).nskeyRotationPolicy(ns),
    );
    root = PqSigningRoot(_atClient, keysIo: keysIo);
    chain = PqSigningChain(_atClient);
    minting = SigningKeyMinting(_atClient);
    keyPackageMinting = KeyPackageMinting(_atClient);
  }

  final AtClient _atClient;
  final AtKeysIo? _keysIo;
  final EnrollmentPrivilegeResolver _privilege;
  final Future<int> Function() _sweepUnanchored;
  final PqStartupGates _gates;

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

  bool _stopped = false;

  /// Halts the startup at the next step boundary. A step already running
  /// finishes — steps are atomic — but no further step starts, so a
  /// stopped client stops publishing. Idempotent; [startupComplete] still
  /// completes.
  void stop() {
    _stopped = true;
    // NOTE: without this a stopped client keeps a periodic timer, a sync
    // listener and a notification subscription alive for the life of the
    // process.
    sharing.stopListening();
  }

  /// Runs the ordered steps. Fired unawaited by the client's init;
  /// idempotent — a second call returns [startupComplete] without
  /// re-running anything.
  Future<void> startup() async {
    if (_started) return startupComplete;
    _started = true;

    // NOTE: assigned here rather than in the constructor, because an
    // application names its crypto configuration after the client is built.
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
      _startupComplete.complete();
    }
  }

  /// Says what a stopped startup did not do, at **warning**.
  ///
  /// `warning` rather than `info` because the only symptom surfaces at the far
  /// end, where a peer reports this atSign as having no published key — so
  /// silence here attributes the failure to the wrong party.
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

  /// The ordered startup steps, each with the name [stepNamesInOrder] reports.
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
  /// serve.
  Future<void> _hydrateHeldSecrets() async {
    if (!_gates.hydrateHeldSecrets) return;
    final keysIo = _keysIo;
    if (keysIo == null) return;
    try {
      await seeding.hydrateStoreFromFiling(sharing);

      // NOTE: the signing root is atSign-level and has no namespace of its
      // own, so it is offered under the client's namespace, which is where
      // requesters ask.
      final askIn = _atClient.getPreferences()?.namespace;
      if (askIn == null || askIn.isEmpty) return;
      if (await root.privateHalf(_atSign) == null) return;

      // NOTE: a private corresponding to nothing published blocks its own
      // repair — it satisfies the pull's "already holding it" guard, so this
      // enrollment never asks — which is why it is reconciled before being
      // offered.
      if (await root.reconcileHeldPrivate(_atSign)) return;

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
  /// ⚠️ With no listener running, a client's only sweep is the one-shot at its
  /// own start, so another enrollment's request for a secret arriving
  /// afterwards is never seen and never answered.
  ///
  /// Stopped by [stop], which the client's teardown calls.
  Future<void> _startEnvelopeListener() async {
    if (!_gates.startEnvelopeListener) return;
    try {
      await sharing.startListening();
    } catch (e) {
      logSwallowed(
          _logger,
          e,
          'Could not start the envelope listener for $_atSign; '
          'this client will not answer other enrollments\' secret requests '
          'and will not pick up envelopes that arrive later: $e');
    }
  }

  /// Files the key material conveyed to this enrollment — the only route by
  /// which a conveyed nskey private reaches the keyfile.
  Future<void> _collectConveyedKeys() async {
    if (!_gates.collectConveyedKeys) return;
    final keysIo = _keysIo;
    if (keysIo == null) return;
    try {
      // NOTE: `ring:` so the sweep files through this client's one filing
      // rather than building a second, whose events nothing can hear.
      await collectConveyedKeyMaterial(_atClient, keysIo, ring: ring);
    } catch (e, st) {
      logSwallowed(
          _logger,
          e,
          'Collecting conveyed key material failed for $_atSign; '
          'this enrollment holds only what it already had, and the next '
          'start retries: $e, $st');
    }
  }

  /// Mints, advertises and files a signing key for every algorithm the in-use
  /// set names and this enrollment does not hold, and retires every one it
  /// holds that the set no longer names.
  ///
  /// Runs before every step that **publishes** — the namespace-key seeding and
  /// both link publications — so a key minted on this start is already
  /// advertised by the time one of those signs with it, and a key retired on
  /// this start signs nothing more. Not before everything that signs: the
  /// sweep steps run first and reply with whatever the keyfile already holds.
  Future<void> _mintInUseSigningKeys() async {
    try {
      if (!_gates.mintInUseSigningKeys) return;
      await minting.reconcileSigningKeys();
    } catch (e, st) {
      _logger.warning('Minting this enrollment\'s own signing keys failed for '
          '$_atSign; it keeps signing with the key it already advertises, and '
          'the next start retries: $e, $st');
    }
  }

  /// Brings this enrollment's advertised key package into line with
  /// `AtClientPreference.keyEstablishmentAlgorithms`.
  ///
  /// Runs **after** the signing keys and before anything that publishes,
  /// because the key package is signed by whatever key `_apsk` advertises:
  /// running it first would sign the package with a key this start is about to
  /// retire, and a peer refusing the package refuses to seal to this
  /// enrollment at all.
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
  /// unreadable the moment this process ends.
  Future<void> _seedNamespaceKeys() async {
    if (!_gates.seedNamespaceKeys) return;
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
  /// Placed before anchoring, which needs the private, so on a start where an
  /// answer is already waiting both succeed in one pass.
  Future<void> _requestRootPrivate() async {
    if (!_gates.requestRootPrivate) return;
    try {
      // NOTE: the request rides the client's own namespace, because that is
      // where its key package is registered and so where holders can be
      // enumerated. A client with no namespace has nowhere to ask.
      final askIn = _atClient.getPreferences()?.namespace;
      if (askIn == null || askIn.isEmpty) return;
      await root.requestPrivateIfAbsent(
        isFullyPrivileged: _privilege.isFullyPrivileged,
        sharing: sharing,
        namespace: askIn,
      );
    } catch (e, st) {
      logSwallowed(
          _logger,
          e,
          'Could not ask for the signing root private for '
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

  /// Anchors this enrollment directly to its signing root, attempted before
  /// the chain link because it needs no hop through whoever approved it.
  Future<void> _publishRootLink() async {
    if (!_gates.publishRootLink) return;
    try {
      await chain.publishOwnRootLink(
          isFullyPrivileged: _privilege.isFullyPrivileged, keysIo: _keysIo);
    } catch (e, st) {
      logSwallowed(
          _logger,
          e,
          'Anchoring $_atSign to its signing root failed; the '
          'enrollment falls back to its approval-chain link and the next '
          'start retries: $e, $st');
    }
  }

  Future<void> _publishChainLink() async {
    if (!_gates.publishChainLink) return;
    try {
      await chain.publishPendingLink();
    } catch (e, st) {
      logSwallowed(
          _logger,
          e,
          'Publishing the approval-chain link failed for '
          '$_atSign; the enrollment stays unsigned, which verifiers '
          'tolerate, and the next start retries: $e, $st');
    }
  }

  /// The chain sweep: a fully privileged client signs and conveys links for
  /// approved enrollments that lack one.
  ///
  /// Gated on privilege here rather than inside, because a link signed by an
  /// unanchored sweeper adds a hop without reaching the root.
  Future<void> _sweepUnanchoredEnrollments() async {
    if (!_gates.sweepUnanchoredEnrollments) return;
    try {
      if (await _privilege.isFullyPrivileged()) {
        await _sweepUnanchored();
      }
    } catch (e, st) {
      logSwallowed(
          _logger,
          e,
          'The chain sweep failed for $_atSign; unanchored '
          'enrollments stay unanchored, which verifiers tolerate, and the '
          'next privileged start retries: $e, $st');
    }
  }

  /// Records what the atServer's enrollment record says about this
  /// enrollment — its `namespaces`, `appName` and `deviceName` — on the
  /// keyfile.
  ///
  /// Runs on **every** start rather than once, because a grant can change
  /// after the file was written.
  ///
  /// ⚠️ **Only for an enrollment the keyfile already holds.** Recording a
  /// snapshot *creates* the slot when it is missing, and an enrollment slot
  /// is typed content ([AtKeys.toJson] treats a non-empty `enrollments` as
  /// exactly that) — so doing this for an enrollment with no material would
  /// rewrite a legacy-flat keyfile as a version 1 document purely as a side
  /// effect of having opened it.
  ///
  /// Writes through [WrittenAtKeysIo.update], the store's atomic verb, because
  /// several start-time writers share the one file and a hand-rolled read →
  /// mutate → flush loses whichever flushes second.
  Future<void> _reconcileEnrollmentSnapshot() async {
    if (!_gates.reconcileEnrollmentSnapshot) return;
    final keysIo = _keysIo;
    if (keysIo is! WrittenAtKeysIo) return;

    // NOTE: the atSign's own credential has no record to fetch, and
    // `enroll:fetch` is answered for whatever id it is handed rather than
    // refused.
    final enrollmentId = _atClient.enrollmentId;
    if (enrollmentId == null || isAtSignCredential(enrollmentId)) return;

    try {
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
  /// An entry whose value is not a string is **skipped rather than
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
    // NOTE: a null incoming field leaves the held one alone, so it cannot
    // disagree.
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
  /// Derived from [_steps] so the order has one home: the list [startup]
  /// iterates.
  @visibleForTesting
  List<String> get stepNamesInOrder => [for (final step in _steps) step.name];
}
