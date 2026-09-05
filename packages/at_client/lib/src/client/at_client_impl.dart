import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart'
    show AtAuthSession, AtEnrollment, AtKeysIo;
import 'package:at_client/src/enroll/self_retrofit.dart' show retrofitIdentity;
import 'package:at_client/src/enroll/pq_native_onboard.dart'
    show firstEnrollmentAppName, firstEnrollmentDeviceName;
import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/at_reachability.dart';
import 'package:at_client/src/client/data_event.dart';
import 'package:at_client/src/client/local_secondary.dart';
import 'package:at_client/src/client/remote_secondary.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart'
    show NskeySeeding;
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/util/encryption_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/collections/collections.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart';
import 'package:at_client/src/service/enrollment_privilege_resolver.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/sync/at_sync_queue.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/storage/hive_at_client_storage.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_client/src/service/file_transfer_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    as resolved_algo;
import 'package:at_client/src/stream/at_stream_notification.dart';
import 'package:at_client/src/stream/at_stream_response.dart';
import 'package:at_client/src/stream/file_transfer_object.dart';
import 'package:at_client/src/stream/stream_notification_handler.dart';
import 'package:at_client/src/transformer/request_transformer/get_request_transformer.dart';
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/get_response_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/put_response_transformer.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/constants.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

/// Implementation of the [AtClient] interface.
class AtClientImpl implements AtClient {
  AtClientPreference? _preference;

  AtClientPreference? get preference => _preference;
  late final Atsign _atSign;

  @override
  Atsign get atSign => _atSign;
  AtKeyValueStore<String, AtData, AtMetaData?>? _localSecondaryKeyStore;

  /// The keystore and sync queue this client holds; null when an external
  /// keystore was injected or storage is not required.
  AtClientStorage? _storage;

  @visibleForTesting
  AtClientStorage? get storage => _storage;
  @visibleForTesting
  LocalSecondary? localSecondary;
  RemoteSecondary? _remoteSecondary;
  static final upperCaseRegex = RegExp(r'[A-Z]');

  PutRequestTransformer putRequestTransformer = PutRequestTransformer();

  @override
  // ignore: override_on_non_overriding_member
  AtChops? _atChops;

  AtKeysIo? _atKeysIo;

  EncryptionService? _encryptionService;

  @experimental
  AtTelemetryService? _telemetry;

  @override
  @experimental
  set telemetry(AtTelemetryService? telemetryService) {
    _telemetry = telemetryService;
    _cascadeSetTelemetryService();
  }

  @override
  @experimental
  AtTelemetryService? get telemetry => _telemetry;

  @override
  set atChops(AtChops? atChops) {
    _atChops = atChops;
    if (_remoteSecondary != null) {
      _remoteSecondary!.atChops = atChops;
    }
  }

  @override
  AtChops? get atChops => _atChops;

  @override
  AtKeysIo? get atKeysIo => _atKeysIo;

  /// Keeps track of CryptoProviders registered with this AtClient
  // ---------------------------------------------------------------------------
  // DataEvent stream — fires on every successful keystore mutation that
  // passes through `LocalSecondary._update` or `LocalSecondary._delete`,
  // which call into [emitDataEvent]. Subscribers see local app writes
  // AND sync-applied remote changes via a single uniform stream.
  // putValue (used internally for SDK bookkeeping) intentionally does
  // NOT emit — see the [DataEvent] dartdoc.

  final StreamController<DataEvent> _dataEventsCtrl =
      StreamController<DataEvent>.broadcast();

  /// In-flight emit count. Each [emitDataEvent] call increments this
  /// before scheduling the listener-invocation microtask, and decrements
  /// after the microtask runs. Drives [pendingEmissions]'s
  /// "all events delivered" semantics.
  int _pending = 0;

  /// Completers registered by callers awaiting [pendingEmissions]
  /// while there were already events in flight. Completed and cleared
  /// whenever [_pending] returns to zero.
  final List<Completer<void>> _drainWaiters = [];

  @override
  Stream<DataEvent> get dataEvents => _dataEventsCtrl.stream;

  @override
  Future<void> get pendingEmissions {
    if (_pending == 0) return Future.value();
    final c = Completer<void>();
    _drainWaiters.add(c);
    return c.future;
  }

  @override
  Future<AtReachabilityResult> ensureReachable(String namespace,
          {Duration timeout = const Duration(seconds: 30)}) =>
      _ensureReachable(namespace).timeout(timeout,
          onTimeout: () => const AtReachabilityResult(AtReachability.timedOut));

  Future<AtReachabilityResult> _ensureReachable(String namespace) async {
    final atSign = getCurrentAtSign();
    final bootstrap = _pqBootstrap;
    if (atSign == null || bootstrap == null) {
      return AtReachabilityResult(AtReachability.failed,
          error: StateError('this client has not finished initialising, so it '
              'has no key ring to publish with'));
    }

    // Answered from the argument, ahead of every round trip below: `*` and
    // `__manage` are grants over other namespaces rather than namespaces data
    // lives in, so no start of any client will ever publish a key for them and
    // asking again later cannot change that.
    if (!NskeySeeding.isSeedable(namespace)) {
      return const AtReachabilityResult(AtReachability.notAuthorised);
    }

    try {
      // Cheapest first, and it is the common case on every start after the
      // one that minted: the atServer's copy, not local storage, because a
      // key another enrollment published a moment ago is absent locally until
      // sync catches up and reading that absence as a cold start is what
      // publishes a second key over the first.
      if (await bootstrap.ring.publishedAdvertisement(atSign, namespace) !=
          null) {
        return const AtReachabilityResult(AtReachability.alreadyReachable);
      }

      // An app that chose a posture which does not seed is not waiting for
      // something that is coming, so it hears so here rather than at the
      // timeout.
      if (_preference?.seedNamespaceKeys != true) {
        return const AtReachabilityResult(AtReachability.postureDoesNotSeed);
      }

      // Nothing here reads what this enrollment was granted. That costs a
      // round trip on an APKAM client and buys nothing for correctness: the
      // atServer refuses a write into a namespace the enrollment does not
      // hold, under the verb's own name, so an ungranted namespace arrives as
      // that refusal — which names the write — instead of as a guess made a
      // round trip earlier. Leaving it out also shortens the window between
      // the read above and the one the seed makes, in which a sibling
      // enrollment can publish.

      // ⚠️ Do NOT call this concurrently with the PQ startup step or with
      // itself. This comment claimed the opposite until 2026-08-27 — that both
      // would re-read under the mint lock and the loser would adopt. The lock
      // excludes a different enrolment; two racers of the SAME one both read
      // the lock back, both see their own id, and both mint. `MintLock` now
      // holds an in-flight guard for the ring this client uses, which is what
      // makes the call safe HERE — not the lock, and not the re-read.

      // The rotation question is not put on this route. A sibling enrollment
      // that published between the read above and the seed's own read routes
      // the seed onto the branch that would put it, and what this route has to
      // say about a namespace that already has a generation is "already
      // reachable" — never "let us consider replacing it".
      await bootstrap.seeding
          .seedNamespace(atSign, namespace, askRotationPolicy: false);
      return const AtReachabilityResult(AtReachability.published);
    } catch (e) {
      _logger.warning('Could not make $atSign reachable for $namespace: $e');
      return AtReachabilityResult(AtReachability.failed, error: e);
    }
  }

  /// Pushes [e] onto [dataEvents] asynchronously (microtask-scheduled).
  /// Called from [LocalSecondary]'s update/delete chokepoints. Public on
  /// [AtClientImpl] only because [LocalSecondary] needs to invoke it
  /// across the class boundary; not part of the [AtClient] interface.
  @internal
  void emitDataEvent(DataEvent e) {
    _pending++;
    scheduleMicrotask(() {
      try {
        if (!_dataEventsCtrl.isClosed) _dataEventsCtrl.add(e);
      } finally {
        if (--_pending == 0 && _drainWaiters.isNotEmpty) {
          final waiters = List<Completer<void>>.from(_drainWaiters);
          _drainWaiters.clear();
          for (final c in waiters) {
            if (!c.isCompleted) c.complete();
          }
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Event-driven expiry timer. Arms a one-shot Timer at
  // LocalSecondary.nextExpiryAt(); on fire, drives a sweep via
  // LocalSecondary.deleteExpiredKeys (whose deletes go through _delete
  // and emit DataDeleted events). _expirySweepInFlight suppresses
  // re-arms triggered by the sweep's own emissions — one re-arm at the
  // end picks up the post-sweep state including any mid-sweep writes.
  Timer? _expiryTimer;
  StreamSubscription<DataEvent>? _expirySub;
  bool _expirySweepInFlight = false;

  // Monotonic guard for the async `_armExpiryTimer`. Each arm claims a
  // generation; after its `await` it bails if a newer arm has started (or the
  // client has stopped), so concurrent listener-driven arms can't orphan each
  // other's one-shot timer and an in-flight arm can't re-arm after stop().
  int _expiryArmGen = 0;

  /// Floor on the expiry timer's delay after a sweep that removed nothing.
  ///
  /// `nextExpiryAt()` reports the earliest expiry in the store **including
  /// ones already past** — unlike its sibling `nextAvailableAt()`, which
  /// excludes crossings that have already happened. A past expiry therefore
  /// arms `Duration.zero`, on the assumption that the sweep about to run will
  /// remove the record and move the minimum forward.
  ///
  /// That assumption fails for a record the client cannot delete: the sweep
  /// logs the refusal, the record stays, the minimum does not move, and the
  /// next arm is `Duration.zero` again. Nothing in that cycle can change its
  /// own outcome, so it spins at event-loop speed for the life of the client.
  /// It is reachable in normal operation — an nskey mint lock is released by
  /// its ttl and by nothing else, so every mint leaves a record that expires
  /// in place.
  ///
  /// The floor keeps the retry (a refusal can be transient, and a later
  /// expiry still needs collecting) while making a fruitless sweep cost one
  /// pass per interval instead of thousands per second.
  static const Duration _fruitlessExpirySweepBackoff = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // Event-driven availability timer. Symmetric counterpart to the
  // expiry timer above — arms at LocalSecondary.nextAvailableAt(); on
  // fire, walks every key whose availableAt has crossed now, emits
  // DataUpdated for each, and re-arms at the next pending availableAt.
  // Drives the visibility-onset event for records whose availableAt
  // is set in the future at write time. _availableSweepInFlight
  // suppresses re-arms during the sweep's own emissions.
  Timer? _availableTimer;
  StreamSubscription<DataEvent>? _availableSub;
  bool _availableSweepInFlight = false;

  // Monotonic guard for the async `_armAvailableTimer` — see `_expiryArmGen`.
  int _availableArmGen = 0;

  SyncService? _syncService;

  @override
  set syncService(SyncService syncService) {
    _syncService = syncService;
    _finalizer.attach(_syncService!, 'SyncService for $_atSign');

    // Coarse forward secrecy's eviction trigger. Deleting a content key's
    // conveyance record stops anyone unwrapping that key again, but every
    // client that already unwrapped it holds the plaintext and would go on
    // reading data the deletion was meant to close off. Sync is what carries
    // the deletion to them, so this is where it becomes an eviction.
    //
    // Registered here rather than where the providers are built, because that
    // runs during construction and the sync service does not exist yet.
    final cache = CryptoConfig.forClient(this).contentKeyCache;
    if (cache != null) {
      syncService.addProgressListener(ContentKeyEviction(cache));
    }
  }

  @override
  SyncService get syncService {
    if (_syncService == null) {
      _logger.info('AtClient ($_atSign) isStopped: $isStopped');
      throw StateError('SyncService has not yet been set');
    }
    return _syncService!;
  }

  NotificationService? _notificationService;

  @override
  set notificationService(NotificationService notificationService) {
    _notificationService = notificationService;
    _finalizer.attach(
      _notificationService!,
      'NotificationService for $_atSign',
    );
  }

  @override
  NotificationService get notificationService {
    if (_notificationService == null) {
      _logger.info('AtClient ($_atSign) isStopped: $isStopped');
      throw StateError('notificationService has not yet been set');
    }
    return _notificationService!;
  }

  EnrollmentService? _enrollmentService;

  @override
  set enrollmentService(EnrollmentService? enrollmentService) {
    _enrollmentService = enrollmentService;
    if (enrollmentService != null) {
      _logger.info('AtClient ($_atSign) isStopped: $isStopped');
      _finalizer.attach(enrollmentService, 'EnrollmentService for $_atSign');
    }
  }

  @override
  EnrollmentService? get enrollmentService {
    if (_enrollmentService == null) {
      throw StateError('EnrollmentService has not yet been set');
    }
    return _enrollmentService;
  }

  @override
  EncryptionService? get encryptionService => _encryptionService;

  late final AtSignLogger _logger;

  /// For the few static contexts (the service [Finalizer]) that cannot use
  /// the per-instance logger.
  static final AtSignLogger _staticLogger = AtSignLogger('AtClientImpl');

  PqClientBootstrap? _pqBootstrap;

  /// This client's PQ startup — the owner of the one key ring, filing,
  /// secret-sharing and signing-root instance set, and of the ordered
  /// fire-and-forget startup steps. Null only for a client whose `_init`
  /// has not run (a cached instance re-served by [create] keeps the one it
  /// was built with). Await its `startupComplete` to know the startup tail
  /// has finished — tests do; production code must not.
  @experimental
  PqClientBootstrap? get pqBootstrap => _pqBootstrap;

  @override
  String? enrollmentId;

  /// The PKAM signing algorithm this client's connections authenticate with.
  ///
  /// Resolved from the enrollment's key material at init
  /// ([_resolveSigningAlgoFromKeyMaterial]) — the algorithm is a fact about
  /// the key you hold, not a preference; the preference's value is the
  /// fallback for a legacy enrollment with no typed material. Every
  /// connection the client owns — verb, monitor, sync — must sign with this,
  /// or a reconnect re-authenticates with the wrong routine against the
  /// record-authoritative atServer.
  ///
  /// Deliberately NOT on the [AtClient] interface: the published interface
  /// has no such member, and adding one breaks every external
  /// `implements AtClient`. Interface-typed callers use [signingAlgoOf].
  /// The resolution itself is recorded in `resolved_signing_algo.dart`,
  /// below the impl layer, so the signing mixins can read it without
  /// depending on this class.
  SigningAlgoType get signingAlgoType => resolved_algo.signingAlgoOf(this);

  /// The PKAM signing algorithm [atClient]'s connections authenticate with:
  /// the key-material resolution when one was recorded at init, else the
  /// preference — the legacy fallback — because the [AtClient] interface
  /// deliberately carries no such member (see [signingAlgoType]).
  static SigningAlgoType signingAlgoOf(AtClient atClient) =>
      resolved_algo.signingAlgoOf(atClient);

  /// Every client this PROCESS has built, keyed by [instanceKey] — the
  /// `(atSign, enrollmentId)` pair, since two enrollments of one atSign are
  /// different principals and must not share a client.
  ///
  /// It is static, so it outlives any individual [AtClientManager]:
  /// `AtClientManager.reset()` nulls the manager's current client and drops its
  /// listeners, and every entry here survives that. [create] consults this
  /// before building anything, which is why passing different arguments for an
  /// atSign already built does not produce a different client — see [create].
  ///
  /// ⚠️ **Clearing an entry does not stop what it held.** This is a plain map:
  /// removing a client drops the reference and nothing else, so its keystore
  /// timers, data-event stream, sync and notification services and open Hive
  /// boxes all keep running, unreferenced. A test that clears this to force a
  /// fresh build should stop the clients it is discarding first, or accept that
  /// they go on doing work for the rest of the process — and must not clear it
  /// while another service has an operation in flight.
  @visibleForTesting
  static final Map atClientInstanceMap = <String, AtClient>{};

  /// Instance keys this process has seen superseded, old key to new key.
  ///
  /// A self-retrofit replaces the enrollment a client authenticates as, and the
  /// old id does not stop existing: the atServer caps it rather than deleting
  /// it, and any caller that captured it earlier still holds it. Without this,
  /// naming the old id misses the cache and builds a **second** client for the
  /// same enrollment — a second connection, a second `_init`, a second startup
  /// tail taking the same mint locks — which is then filed over the first,
  /// leaving the original alive and unreachable.
  ///
  /// Measured 2026-08-28 against a live atServer: `create` naming the
  /// superseded id returned a client that was not `identical` to the first,
  /// carrying the same settled enrollment id, and the instance map came back
  /// with the same single key — the second had replaced the first.
  ///
  /// ⚠️ **No caller in this repository names a superseded id**; the path was
  /// found by probe. It is closed for the application that persists an
  /// enrollment id — displays it, stores it in config — and builds a client
  /// with it after a retrofit has moved on.
  ///
  /// Deliberately a separate map rather than an alias entry in
  /// [atClientInstanceMap]: an alias would make one client look like two to
  /// the enrolled-client count in [_resolveCacheKey], whose whole job is to
  /// tell "exactly one enrolled client" from "several".
  @visibleForTesting
  static final Map<String, String> supersededInstanceKeys = <String, String>{};

  /// Follows [asked] through any supersessions to the key a client is actually
  /// filed under.
  ///
  /// Only ever moves to a key [atClientInstanceMap] holds. Tests clear and
  /// remove from that map directly, so a supersession whose target has been
  /// evicted must leave the caller where it started rather than send it to a
  /// key nothing answers for.
  static String _currentInstanceKey(String asked) {
    var key = asked;
    final seen = <String>{asked};
    while (true) {
      final next = supersededInstanceKeys[key];
      if (next == null ||
          !atClientInstanceMap.containsKey(next) ||
          !seen.add(next)) {
        return key;
      }
      key = next;
    }
  }

  /// The cache key for a client of [atSign] authenticated as [enrollmentId].
  ///
  /// **Identity here is `(atSign, enrollmentId)`, not the atSign alone.** A
  /// client authenticated as one enrollment is a different principal from one
  /// authenticated as another, or as the atSign's own keys: it holds a
  /// different APKAM keypair, is granted different namespaces, and the atServer
  /// answers `enroll:listns` for it and not for the others. Keying on the
  /// atSign alone silently handed every caller the first client built for that
  /// atSign, so a second enrollment of one atSign could not exist in a process
  /// — `identical(second, first)` was true, and the enrollment id never reached
  /// the connection because `_remoteSecondary ??=` kept the original.
  ///
  /// A null [enrollmentId] keeps the bare atSign as the key. That is the
  /// overwhelmingly common case — a client using the atSign's own keys — and
  /// leaving its key unchanged means no existing caller, cache eviction or
  /// termination path has to learn a new shape.
  static String instanceKey(String atSign, String? enrollmentId) =>
      enrollmentId == null ? atSign : '$atSign|$enrollmentId';

  /// The key [create] should look under, given what the caller named.
  ///
  /// A caller that names no enrollment usually means *this atSign's client*
  /// rather than *a client belonging to no enrollment* — `at_activate`'s
  /// `otp`, `list` and `spp` build their client through `createAtClient`, which
  /// names none, and most tests do the same. Taking `null` literally hands
  /// those callers a brand-new client carrying no key material, which does not
  /// fail here: it fails much later, on the first verb, as
  /// `PKAM Keypair required for signing`. That is exactly what made
  /// `end2end_test_14` fail once `enrollment_setup` had written an enrollment
  /// id into the keyfile, while trunk — which keyed this cache on the atSign
  /// alone — returned the enrolled client and worked.
  ///
  /// So an unnamed enrollment falls back to the atSign's client when there is
  /// exactly ONE. **Only one.** Two enrollments of an atSign are two
  /// principals, and silently picking either would hand a caller credentials
  /// it did not ask for — the identity hazard this cache key exists to close.
  /// With several, this refuses and says which ids are available, because a
  /// caller that cannot say which principal it wants has a bug that a guess
  /// would hide.
  ///
  /// One consequence, and it is the desirable one: a caller whose preference
  /// names different rollout axes from the enrolled client it now lands on is
  /// refused by [refuseChangedRolloutAxes] rather than quietly handed a client
  /// running a stage it thinks it has left. Before this fallback that caller
  /// got its own client and no refusal — but the client could not authenticate,
  /// so the failure simply moved to the first verb and lost its explanation on
  /// the way.
  static String _resolveCacheKey(String atSign, String? enrollmentId) {
    final asked = _currentInstanceKey(instanceKey(atSign, enrollmentId));
    if (enrollmentId != null || atClientInstanceMap.containsKey(asked)) {
      return asked;
    }
    final enrolled = atClientInstanceMap.keys
        .whereType<String>()
        .where((key) => key.startsWith('$atSign|'))
        .toList();
    if (enrolled.isEmpty) return asked;
    if (enrolled.length == 1) return enrolled.single;
    throw ArgumentError.value(
        enrollmentId,
        'enrollmentId',
        'no enrollment id was given for $atSign, and ${enrolled.length} '
            'enrolled clients exist for it '
            '(${enrolled.map((k) => k.split('|').last).join(', ')}). '
            'They are different principals, so name the one you want.');
  }

  /// Throws when [asked] names different rollout axes from the client that is
  /// already running under [cacheKey] — the posture, the signing rollout, the
  /// in-use signing set or the legacy-encryption refusal.
  ///
  /// Every one of those is final at construction, so a client that already
  /// exists cannot adopt them; the choice is between refusing and ignoring,
  /// and ignoring is what this used to do. What that cost is not a flag: after
  /// the auth/signing split the stage decides which algorithm an enrollment
  /// authenticates with and which signing key it holds, so a caller whose
  /// preference was ignored runs on the wrong **key** and finds out when a
  /// peer cannot verify it.
  ///
  /// Static and shared because two paths hand back a client that already
  /// exists, and only one of them is this class: `AtClientManager`'s
  /// same-atSign short-circuit returns without calling [create] at all. A
  /// guard on the cache alone would be loud on the path a caller reaches with
  /// an override argument and silent on the ordinary one.
  ///
  /// An [ArgumentError], not an [AtClientException]: this is a caller
  /// programming error — two places in one app disagreeing about the stage —
  /// rather than anything the atServer or the network did.
  static void refuseChangedRolloutAxes({
    required AtClientPreference? running,
    required AtClientPreference asked,
    required String cacheKey,
  }) {
    if (running == null) return;
    final differences = running.rolloutDifferencesFrom(asked);
    if (differences.isEmpty) return;
    throw ArgumentError.value(
        differences.join('; '),
        'preference',
        'the client for $cacheKey is already running under different rollout '
            'settings, and they are final at construction — it cannot adopt '
            'these. Stop that client before building one with different '
            'settings, or give this preference the settings it is running '
            'under. Ignoring the difference would leave this caller writing, '
            'signing and enrolling under a stage it thinks it has left');
  }

  /// Refuses a preference naming a different [AtClientPreference.hiveStoragePath]
  /// from the one this client's store is already open at.
  ///
  /// Separate from [refuseChangedRolloutAxes] because it is a different kind of
  /// claim: the rollout axes decide what a client *writes*, this decides
  /// *where*. `rolloutDifferencesFrom` says in its own dartdoc that what it
  /// compares is the whole of what a posture can change, and a storage path is
  /// not one of those.
  ///
  /// **Why refusing rather than adopting.** `StorageManager` opens the Hive
  /// bundle once, at the first path it is given, and nothing reopens it — so a
  /// later path is not applied however it is delivered. Adopting it silently
  /// leaves the caller believing its data is going somewhere it is not, and
  /// [setPreferences] is worse still: it would make the client *report* a path
  /// it never used. That is the same failure the rollout guard beside this one
  /// exists to stop, and it gets the same answer.
  ///
  /// A null [AtClientPreference.hiveStoragePath] on [asked] is not a conflict:
  /// a caller that named no path is not asking for a different one.
  ///
  /// An [ArgumentError] for the same reason as its sibling — two places in one
  /// app disagreeing about where this atSign's data lives is a caller
  /// programming error, not something the atServer did.
  static void refuseChangedStoragePath({
    required AtClientPreference? running,
    required AtClientPreference asked,
    required String cacheKey,
  }) {
    if (running == null) return;
    final was = running.hiveStoragePath;
    final now = asked.hiveStoragePath;
    if (was == null || now == null || was == now) return;
    throw ArgumentError.value(
        'hiveStoragePath (asked $now, running $was)',
        'preference',
        'the client for $cacheKey already has its local store open at $was, '
            'and nothing reopens it — so $now would never be used. Stop that '
            'client before building one somewhere else, or give this '
            'preference the path it is running under. Ignoring the difference '
            'would leave this caller believing its data is at a path it is '
            'not.');
  }

  static final Finalizer<String> _finalizer = Finalizer((service) {
    _staticLogger.finer('Outgoing $service has been garbage collected');
  });

  // Cache key combines (namespace, eventSource). Two collections on
  // the same namespace with different event sources are independent
  // instances: each has its own listener wiring and pending-events
  // buffer, so sharing one cache slot would conflate their event
  // streams.
  final Map<(String, EventSource), AtCollection> _collections = {};
  final Set<(String, EventSource)> _collectionsSwept =
      <(String, EventSource)>{};

  @override
  Future<AtCollection<T>> collection<T>(
    String namespace,
    Duration defaultExpiration, {
    EventSource eventSource = EventSource.both,
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
    bool cleanupOrphansOnCreation = false,
  }) async {
    if (!namespace.contains('.')) {
      throw ArgumentError(
        'namespace must be fully qualified — provide the complete namespace '
        '(e.g. "tasks.my_app"), NOT just the collection name. The '
        'application namespace from AtClientPreference will NOT be appended '
        'automatically.',
      );
    }
    final cacheKey = (namespace, eventSource);
    final c = _collections.putIfAbsent(
      cacheKey,
      () => AtCollection<T>(
        this,
        namespace,
        defaultExpiration,
        eventSource: eventSource,
        fromJson: fromJson,
        typeTag: typeTag,
      ),
    ) as AtCollection<T>;
    if (cleanupOrphansOnCreation && !_collectionsSwept.contains(cacheKey)) {
      _collectionsSwept.add(cacheKey);
      try {
        await c.cleanupOrphans();
      } catch (e, st) {
        _logger.warning('cleanupOrphans on $namespace failed: $e\n$st');
      }
    }
    return c;
  }

  /// Returns the client for `(currentAtSign, enrollmentId)`, building one only
  /// if this process has not built one already.
  ///
  /// ⚠️ **On a cache hit almost every argument here is ignored, silently.** The
  /// cache is static and keyed only by that pair, so a second call naming the
  /// same atSign and enrollment hands back the FIRST client — built with the
  /// first caller's preference, storage path, collaborators and key source.
  /// What the second caller passed is dropped without a log line, and the only
  /// thing adopted from it is `preferences.crypto`, so that providers added
  /// after first creation take effect.
  ///
  /// Concretely, on a cache hit these do nothing: [remoteSecondary],
  /// [encryptionService], [localSecondaryKeyStore], [atChops], [atKeysIo],
  /// [atLookUp], and every field of [preferences] except `crypto`. An extended
  /// `AtKeys` is meant to be born at construction and immutable after, which is
  /// why the key source in particular is not re-read.
  ///
  /// Two mismatches are **refused** rather than ignored, because accepting them
  /// would leave a caller believing something that is not true: a preference
  /// naming different rollout axes, and one naming a different
  /// `hiveStoragePath` — see [refuseChangedRolloutAxes] and
  /// [refuseChangedStoragePath]. Everything else in the list above fails
  /// quietly, so a test or an app that needs a genuinely different client must
  /// not rely on passing different arguments here.
  ///
  /// Nothing in this library ever removes an entry from that cache, so a client
  /// that has been stopped is returned from here and restarted rather than
  /// rebuilt. A process that needs a second, genuinely separate client for one
  /// atSign — which a test driving several CLI-style operations does — cannot
  /// get it from this method at all.
  static Future<AtClient> create(
    String currentAtSign,
    String? namespace,
    AtClientPreference preferences, {
    @Deprecated('no longer needed. will be removed in a future release')
    AtClientManager? atClientManager,
    RemoteSecondary? remoteSecondary,
    EncryptionService? encryptionService,
    AtKeyValueStore<String, AtData, AtMetaData?>? localSecondaryKeyStore,
    @Deprecated('replaced by atKeysIo, will be removed in the next release')
    AtChops? atChops,
    AtKeysIo? atKeysIo,
    AtLookUp? atLookUp,
    String? enrollmentId,
  }) async {
    currentAtSign = AtUtils.fixAtSign(currentAtSign);

    // Fetch cached AtClientImpl for re-use, or create a new one and init it.
    // Keyed by (atSign, enrollmentId) — see [instanceKey]; two enrollments of
    // one atSign are different principals and must not share a client.
    final cacheKey = _resolveCacheKey(currentAtSign, enrollmentId);
    AtClientImpl? atClientImpl;
    if (atClientInstanceMap.containsKey(cacheKey)) {
      atClientImpl = atClientInstanceMap[cacheKey];
      // Before anything is adopted or started: a cached client keeps the
      // rollout axes it was built under, so a caller handing over a preference
      // that names different ones is asking for something this cannot give.
      refuseChangedRolloutAxes(
          running: atClientImpl!.getPreferences(),
          asked: preferences,
          cacheKey: cacheKey);
      refuseChangedStoragePath(
          running: atClientImpl.getPreferences(),
          asked: preferences,
          cacheKey: cacheKey);
      await atClientImpl.start();
      // Re-using a cached AtClient skips _init. Adopt the supplied preference's
      // crypto config so providers (and a changed defaultProviderId) added
      // after first creation take effect; CryptoRuntime resolves against the
      // live preference.crypto, so there is nothing else to reconcile.
      atClientImpl.getPreferences()?.crypto = preferences.crypto;
      // atKeysIo (like atChops) is only honored on first construction — the
      // extended AtKeys is meant to be born at construction and immutable
      // after, so a re-used cached client keeps its original key source.
    } else {
      atClientImpl = AtClientImpl._(
        currentAtSign,
        namespace,
        preferences,
        remoteSecondary: remoteSecondary,
        encryptionService: encryptionService,
        localSecondaryKeyStore: localSecondaryKeyStore,
        atChops: atChops,
        atKeysIo: atKeysIo,
        atLookUp: atLookUp,
        enrollmentId: enrollmentId,
      );

      await atClientImpl._init(atLookUp: atLookUp);
    }

    // Not [cacheKey]: `_init` may have settled a different identity than the
    // caller asked for, because a posture requiring a stronger authentication
    // key retrofits the client before returning. Filing under the requested id
    // would leave the cache holding a client under an enrollment it no longer
    // authenticates as, and a later create() for the new id would build a
    // second client for one enrollment.
    final filedKey = instanceKey(currentAtSign, atClientImpl.enrollmentId);
    atClientInstanceMap[filedKey] = atClientImpl;
    return atClientInstanceMap[filedKey];
  }

  AtClientImpl._(
    String theAtSign,
    String? namespace,
    AtClientPreference preference, {
    RemoteSecondary? remoteSecondary,
    EncryptionService? encryptionService,
    AtKeyValueStore<String, AtData, AtMetaData?>? localSecondaryKeyStore,
    AtChops? atChops,
    AtKeysIo? atKeysIo,
    AtLookUp? atLookUp,
    this.enrollmentId,
  }) {
    _atSign = theAtSign.toAtsign();
    _logger = AtSignLogger('AtClientImpl ($_atSign)');
    _preference = preference;
    _preference?.namespace ??= namespace;
    // If the app configured a process-wide network timeout, apply it as the
    // single default that bounds every atServer connect / atDirectory lookup /
    // operation. Only mutates the global when explicitly set, so the built-in
    // default otherwise stands.
    if (preference.networkTimeout != null) {
      AtNetworkTimeouts.defaultTimeout =
          AtNetworkTimeouts.cap(preference.networkTimeout!);
    }
    _localSecondaryKeyStore = localSecondaryKeyStore;

    if (_localSecondaryKeyStore != null && !_preference!.isLocalStoreRequired) {
      throw IllegalArgumentException(
        'An AtKeyValueStore was injected, but preference.isLocalStoreRequired is false',
      );
    }

    _remoteSecondary = remoteSecondary;
    _encryptionService = encryptionService;
    _atChops = atChops;
    _atKeysIo = atKeysIo;
  }

  Future<void> _init({AtLookUp? atLookUp}) async {
    // Always an explicit step, never a side effect of building AtChops: a
    // client whose AtChops was injected never builds one, and it must not
    // sign the preference's rsa2048 default under an ML-DSA enrollment.
    await _resolveSigningAlgoFromKeyMaterial();
    if (_preference!.isLocalStoreRequired) {
      AtSyncQueue? syncQueue;
      if (_localSecondaryKeyStore == null) {
        final storagePath = preference!.hiveStoragePath;
        if (storagePath == null) {
          throw Exception('Please set local storage path');
        }
        final storage =
            HiveAtClientStorage(atSign: _atSign, storagePath: storagePath);
        await storage.attach(this);
        _storage = storage;
        syncQueue = storage.syncQueue;
      }

      localSecondary = LocalSecondary(
        this,
        keyStore: _localSecondaryKeyStore ?? _storage?.keyStore,
        syncQueue: syncQueue,
        onEvent: emitDataEvent,
      );
      _atChops ??= await _createAtChops(_atSign);
      _validateDefaultCryptoProvider();

      // Wire the event-driven expiry timer to the data-events stream.
      // Re-arms on every keystore mutation; first arm uses the current
      // cache state (no-op when nothing has TTL).
      _expirySub = dataEvents.listen((_) {
        if (_expirySweepInFlight) return;
        unawaited(_armExpiryTimer());
      });
      await _armExpiryTimer();

      // Symmetric wire-up for the availability timer. SEED the
      // already-fired set BEFORE arming the timer: every cached
      // record whose `availableAt` is in the past at startup gets
      // marked as already-emitted so the first sweep doesn't replay
      // it. Without this, restarting the AtClient against an
      // existing storage-dir would re-emit `DataUpdated` for every
      // such record, which AtCollection forwards as
      // CSubItemUpdated / CItemUpdated — making listeners see a
      // fresh stream of "arrivals" when nothing has actually
      // arrived. The semantic of `_onAvailableFire` is "fire when
      // availableAt JUST CROSSED" — past crossings observed by an
      // earlier process run shouldn't replay on a later one.
      await localSecondary?.seedAvailabilityFiredAsOf(DateTime.timestamp());
      _availableSub = dataEvents.listen((_) {
        if (_availableSweepInFlight) return;
        unawaited(_armAvailableTimer());
      });
      await _armAvailableTimer();
    }

    // Using ??= because we may be injecting a RemoteSecondary
    _remoteSecondary ??= buildRemoteSecondary(atLookUp: atLookUp);

    // Settle which enrollment this client runs as, before anything that
    // derives from it is built.
    await _settleEnrollmentIdentity();

    // Using ??= because we may be injecting an EncryptionService
    _encryptionService ??= EncryptionService(_atSign);
    _encryptionService!.remoteSecondary = _remoteSecondary;
    _encryptionService!.localSecondary = localSecondary;

    putRequestTransformer.atClient = this;

    _cascadeSetTelemetryService();

    // Built before the crypto config adopts its era default, because the
    // config's nskey providers read through the bootstrap's key ring — the
    // same ring the startup steps mint into and file from.
    // A stage that configures no post-quantum providers advertises no key
    // package and asks for no privates. Both steps are otherwise ungated by
    // posture, which left such a client minting an X-Wing package, publishing
    // it, asking peers for privates, filing the answers and then refusing to
    // use any of it. The advertisement is the harmful half: a peer reads it
    // and seals to an atSign whose client then declines the record, so the
    // write is lost to a reader that advertised capability it had switched
    // off. `KeyPackageStatus.absent` is what the substrate documents for "an
    // older client", which is exactly what this stage stands in for.
    _pqBootstrap = PqClientBootstrap(
      this,
      keysIo: _atKeysIo,
      gates: (_preference?.posture.configuresPqProviders ?? true)
          ? const PqStartupGates()
          : const PqStartupGates(
              reconcileKeyPackage: false,
              requestMissingPrivates: false,
              // The sweep signs links and seals secrets, which this posture
              // has no providers for. Gated here as well as refused in
              // `EnrollmentServiceImpl` so the startup does not call a step
              // that would throw: the gate is the startup's answer, the throw
              // is every other caller's.
              sweepUnanchoredEnrollments: false),
      privilege: EnrollmentRecordPrivilegeResolver(this,
          listEnrollments: EnrollmentServiceImpl(this, AtEnrollment.create())
              .fetchEnrollmentRequests),
      sweepUnanchoredEnrollments: () =>
          EnrollmentServiceImpl(this, AtEnrollment.create())
              .sweepUnanchoredEnrollments(),
    );

    _adoptEraCryptoDefault();

    _announceLegacyEncryptionPosture();

    // The PQ startup — seeding, collecting conveyed key material, chain-link
    // publishes — as one ordered fire-and-forget task. Deliberately not
    // awaited: neither a round trip nor a publish is something a client's
    // startup should wait on or fail for, and anything a step missed is
    // retried at the next start. A caller needing the tail to have run can
    // await [pqBootstrap]'s `startupComplete` — but that getter is on this
    // class, not on the `AtClient` interface, so reaching it means casting to
    // `AtClientImpl`. There is no interface-level handle for the tail.
    unawaited(_pqBootstrap!.startup());
  }

  /// Gives this client the era's crypto default: normally the nskey providers
  /// wired for reading, with writes still going out legacy — or, for a posture
  /// that does not read post-quantum data, no post-quantum providers at all.
  ///
  /// **Why the SDK builds this rather than the app.** An app that had to name a
  /// `CryptoConfig` to have one would be pinned to whatever was current the day
  /// it was written, and would sit out the migration it exists to ride. An app
  /// that *does* name one still wins — `adoptEraDefault` leaves it alone.
  ///
  /// The key ring is given this client's `AtKeys` so it can find a private that
  /// was **conveyed** to this enrollment or that survived a restart. Without
  /// that the ring sees only what this process minted itself
  /// (`published_nskey_key_ring.dart`'s `_ownPrivates`), so every restart would
  /// read as "this atSign cannot open its own namespace". A client with no
  /// `AtKeysIo` still gets the providers — reading is additive and costs a
  /// client nothing that does not use it — but has no durable private source,
  /// which is the same limitation it already had.
  ///
  /// Built once per client because these providers hold per-atSign state; a
  /// shared instance would let two atSigns see each other's cached content
  /// keys. The ring is the bootstrap's — the same instance the startup steps
  /// mint into and file from, so a private the seeding step just minted is
  /// visible to the very next read.
  void _adoptEraCryptoDefault() {
    // The posture picks which era set this client is born with: the 3.x
    // default keeps writes legacy, the 4.0 posture makes post-quantum writes
    // the default. Both read everything. An app-named `crypto` still wins —
    // adoptEraDefault leaves it alone either way.
    final writesPq = _preference?.posture.writesPqByDefault ?? false;
    // A posture that does not read post-quantum data registers none of those
    // providers: the era default is the legacy set, so a record stamped with a
    // post-quantum provider id has nothing to resolve to and the read throws
    // instead of opening.
    //
    // The `?? true` cannot fire: `_preference!` is dereferenced earlier in
    // construction, so a client reaching here always has one. It is written
    // this way to match the six neighbouring `_preference?.` reads rather than
    // to describe a reachable state — do not read it as "a client with no
    // preference keeps the providers".
    final readsPq = _preference?.posture.configuresPqProviders ?? true;
    if (!readsPq) {
      CryptoConfig.adoptEraDefault(this, const CryptoConfig.legacy());
      return;
    }
    // The one caller that HAS a preference, so the one that narrows the
    // seal-to list if this deployment asked for that. Everywhere further down
    // defaults to the full list, which refuses nobody.
    final sealsTo =
        _preference?.sealsToKeyAlgorithms ?? SecretSharingAlgos.keyAlgos;
    CryptoConfig.adoptEraDefault(
      this,
      writesPq
          ? CryptoConfig.nskey(
              keyRing: _pqBootstrap!.ring, sealsToKeyAlgorithms: sealsTo)
          : CryptoConfig.readsNskeyWritesLegacy(
              keyRing: _pqBootstrap!.ring, sealsToKeyAlgorithms: sealsTo),
    );
  }

  /// Says out loud, at every client creation, whether this client may still
  /// write legacy-encrypted data.
  ///
  /// At SHOUT because the default is the unsafe one and will be until 4.0.
  /// Anything quieter is a default nobody discovers until the migration is
  /// over — the whole failure mode this project exists to prevent is data
  /// written today under a scheme that is harvestable today and openable
  /// later, by an app whose author never knew it had a choice.
  void _announceLegacyEncryptionPosture() {
    if (_preference?.disallowLegacyEncryption == true) {
      _logger.info('disallowLegacyEncryption is set: this client refuses to '
          'encrypt new data with the legacy provider. Legacy reads are '
          'unaffected.');
      if (_preference?.allowLegacyCryptoFallback == true) {
        _logger.shout(
            'allowLegacyCryptoFallback is set alongside disallowLegacyEncryption '
            'and has no effect — the cold-start fallback is a legacy write, so '
            'a destination with no post-quantum key is refused rather than '
            'reached.');
      }
      return;
    }
    _logger.shout(
        'disallowLegacyEncryption is false, so this client may still encrypt '
        'new data with the legacy (RSA/AES) provider — harvestable now, '
        'openable by a quantum computer later. It becomes the default in '
        'at_client 4.0; set it on AtClientPreference to opt in early.');
  }

  /// Arms (or re-arms) the one-shot expiry [Timer] at the
  /// LocalSecondary's earliest pending expiration. No-op when the
  /// LocalSecondary's event cache reports no TTL'd keys.
  ///
  /// A timestamp in the past arms a `Duration.zero` timer that fires
  /// on the next microtask — effectively immediate.
  /// [afterFruitlessSweep] is set by [_onExpiryFire] when the sweep it just
  /// ran removed no keys. A past expiry then cannot be cleared by firing
  /// again immediately, so the delay is floored at
  /// [_fruitlessExpirySweepBackoff] rather than zero.
  Future<void> _armExpiryTimer({bool afterFruitlessSweep = false}) async {
    final gen = ++_expiryArmGen;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final ls = localSecondary;
    if (ls == null) return;
    final when = await ls.nextExpiryAt();
    // Bail if a newer arm superseded us across the await, or we stopped.
    if (gen != _expiryArmGen || _isStopped) return;
    if (when == null) return;
    final wait = when.difference(DateTime.timestamp());
    _expiryTimer = Timer(
        expiryTimerDelay(wait, afterFruitlessSweep: afterFruitlessSweep),
        _onExpiryFire);
  }

  /// How long to wait before the next expiry sweep, given [untilNextExpiry]
  /// (negative when the earliest expiry is already past).
  ///
  /// A past expiry normally means "sweep now", and the sweep clears the
  /// record so the next one is in the future. When the sweep removed nothing
  /// ([afterFruitlessSweep]) that reasoning does not hold: firing again
  /// immediately re-runs the same computation over the same state, forever.
  /// See [_fruitlessExpirySweepBackoff].
  @visibleForTesting
  static Duration expiryTimerDelay(Duration untilNextExpiry,
      {required bool afterFruitlessSweep}) {
    if (!untilNextExpiry.isNegative) return untilNextExpiry;
    return afterFruitlessSweep ? _fruitlessExpirySweepBackoff : Duration.zero;
  }

  /// Drives one expiry sweep and re-arms the timer for the next.
  /// `_expirySweepInFlight` suppresses re-arms triggered by the
  /// sweep's own `DataDeleted` events; the single re-arm in `finally`
  /// picks up the post-sweep state, including any mid-sweep writes
  /// (the keystore's in-memory cache is updated synchronously inside
  /// each put before the corresponding [DataEvent] microtask runs).
  Future<void> _onExpiryFire() async {
    _expirySweepInFlight = true;
    // Nothing removed means the next arm must not fire immediately: see
    // [_fruitlessExpirySweepBackoff]. A throwing sweep counts as fruitless
    // for the same reason — it cannot have moved the earliest expiry.
    var removed = 0;
    try {
      removed = await localSecondary?.deleteExpiredKeys() ?? 0;
    } catch (e, st) {
      _logger.warning('Expiry sweep failed: $e\n$st');
    } finally {
      _expirySweepInFlight = false;
      await _armExpiryTimer(afterFruitlessSweep: removed == 0);
    }
  }

  /// Arms (or re-arms) the one-shot availability [Timer] at the
  /// LocalSecondary's earliest pending availableAt. No-op when no
  /// cached key has TTB.
  ///
  /// A timestamp in the past arms a `Duration.zero` timer that fires
  /// on the next microtask — covers the rare race where a record's
  /// availableAt slid into the past between the previous re-arm and
  /// this one.
  Future<void> _armAvailableTimer() async {
    final gen = ++_availableArmGen;
    _availableTimer?.cancel();
    _availableTimer = null;
    final ls = localSecondary;
    if (ls == null) return;
    final when = await ls.nextAvailableAt();
    // Bail if a newer arm superseded us across the await, or we stopped.
    if (gen != _availableArmGen || _isStopped) return;
    if (when == null) return;
    final wait = when.difference(DateTime.timestamp());
    _availableTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      _onAvailableFire,
    );
  }

  /// Drives one availability sweep and re-arms the timer for the
  /// next. Walks every key whose `availableAt <= now`, emits a
  /// [DataUpdated] for each, and re-arms in `finally` so a mid-sweep
  /// error doesn't leave the timer disarmed.
  Future<void> _onAvailableFire() async {
    _availableSweepInFlight = true;
    try {
      final ls = localSecondary;
      if (ls == null) return;
      final now = DateTime.timestamp();
      for (final keyStr in await ls.keysWithAvailableAtAtOrBefore(now)) {
        try {
          final atKey = AtKey.fromString(keyStr);
          AtMetaData? meta;
          try {
            meta = await ls.keyStore!.getMeta(keyStr);
          } on Exception {
            meta = null;
          }
          if (meta == null) continue;
          emitDataEvent(DataUpdated(atKey, metadata: meta));
          // Drop from the availability cache so it won't fire again.
          await ls.dropAvailabilityCacheEntry(keyStr);
        } on Exception catch (e) {
          _logger.warning('availability sweep failed for $keyStr: $e');
        }
      }
    } catch (e, st) {
      _logger.warning('Availability sweep failed: $e\n$st');
    } finally {
      _availableSweepInFlight = false;
      await _armAvailableTimer();
    }
  }

  bool _isStopped = false;

  @override
  bool get isStopped => _isStopped;

  Future<void> start() async {
    if (!_isStopped) {
      _logger.finer('start() called, but atClient is not stopped. Ignoring');
      return;
    }
    _isStopped = false;
  }

  @override
  Future<void> stop() async {
    if (_isStopped) {
      _logger.info('stop() called: but client is already stopped. Ignoring.');
      return;
    }

    _isStopped = true;
    _logger.info('stop() called: stopping at_client for $_atSign');

    await _stopBackgroundProcesses();
  }

  Future<void> _stopBackgroundProcesses() async {
    // First, so a stopped client publishes nothing further: the PQ startup
    // halts at its next step boundary.
    _pqBootstrap?.stop();
    try {
      _expiryTimer?.cancel();
      _expiryTimer = null;
      await _expirySub?.cancel();
      _expirySub = null;
      _availableTimer?.cancel();
      _availableTimer = null;
      await _availableSub?.cancel();
      _availableSub = null;
      if (!_dataEventsCtrl.isClosed) await _dataEventsCtrl.close();
    } catch (e) {
      _logger.warning('Error while tearing down keystore-event timers: $e');
    }

    try {
      await (_syncService as SyncServiceImpl).stop();
    } catch (e) {
      _logger.warning('Error while closing sync service: $e');
    }

    try {
      await (_notificationService as NotificationServiceImpl).stop();
    } catch (e) {
      _logger.warning('Error while closing notification service: $e');
    }

    if (_remoteSecondary != null) {
      try {
        await _remoteSecondary!.closeConnection();
      } catch (e) {
        _logger.warning('Error while closing remote secondary connection: $e');
      }
    }

    _syncService = null;
    _notificationService = null;
    _enrollmentService = null;
  }

  @Deprecated(
    'Commit-log compaction was removed with the commit-log-free keystore; '
    'this is now a no-op and will be removed in a future major release',
  )
  @override
  Future<void> startCompactionJob({
    Duration? commitLogCompactionDuration,
  }) async {
    // No-op: the commit-log-free client has no commit log to compact.
  }

  @Deprecated(
    'Commit-log compaction was removed with the commit-log-free keystore; '
    'this is now a no-op and will be removed in a future major release',
  )
  @override
  Future<void> stopCompactionJob() async {
    // No-op: the commit-log-free client has no commit log compaction job.
  }

  void _cascadeSetTelemetryService() {
    // if (telemetry != null) {
    //   _encryptionService?.telemetry = telemetry;
    //   _localSecondary?.telemetry = telemetry;
    //   _remoteSecondary?.telemetry = telemetry;
    // }
  }

  @override
  LocalSecondary? getLocalSecondary() {
    return localSecondary;
  }

  @override
  AtPersistenceBundle? get persistenceBundle {
    final storage = _storage;
    return storage is HiveAtClientStorage ? storage.bundle : null;
  }

  @override
  RemoteSecondary? getRemoteSecondary() {
    return _remoteSecondary;
  }

  /// Builds a [RemoteSecondary] that authenticates as **this client**: the
  /// enrollment id settled at init, and the PKAM signing algorithm resolved
  /// from that enrollment's key material rather than the preference's
  /// deprecated default.
  ///
  /// Every site in this class that opens a connection goes through here, so
  /// that carrying the client's identity is a property of the class rather
  /// than something each site has to remember. A site that forgot signed the
  /// challenge with the wrong routine, which under an ML-DSA enrollment throws
  /// out of at_chops rather than failing authentication — a shape that reads
  /// as a client bug wherever it surfaces.
  ///
  /// [atLookUp] injects an already-built lookup; passing none lets
  /// [RemoteSecondary] open its own connection, which is what a site wanting a
  /// connection separate from the client's shared one does.
  @visibleForTesting
  RemoteSecondary buildRemoteSecondary({AtLookUp? atLookUp}) => RemoteSecondary(
        _atSign,
        _preference!,
        atChops: atChops,
        atLookUp: atLookUp,
        privateKey: _preference!.privateKey,
        enrollmentId: enrollmentId,
        signingAlgoType: signingAlgoType,
        atKeysIo: _atKeysIo,
      );

  @override

  /// Replaces this client's preference — everything except the rollout axes,
  /// which are **refused** when they differ.
  ///
  /// Naming the replacement rather than being handed one does not make the
  /// change possible: `posture`, `authenticationKeyAlgorithm`,
  /// `dataSigningKeyAlgorithms` and `disallowLegacyEncryption` are final at
  /// construction because the
  /// substrate reads them once, at a startup that has already run by the time
  /// anyone can call this. Accepting them here would leave the client
  /// *reporting* a stage it never applied, which is worse than the silent drop
  /// [create] used to do — there the caller at least kept the stage it was
  /// running under.
  ///
  /// Everything else is replaced as before, `crypto` included.
  @override
  void setPreferences(AtClientPreference preference) async {
    refuseChangedRolloutAxes(
        running: _preference,
        asked: preference,
        cacheKey: instanceKey('$_atSign', enrollmentId));
    refuseChangedStoragePath(
        running: _preference,
        asked: preference,
        cacheKey: instanceKey('$_atSign', enrollmentId));
    _preference = preference;
  }

  Future<bool> persistPrivateKey(String privateKey) async {
    var atData = AtData();
    atData.data = privateKey.toString();
    await localSecondary!.keyStore!.put(AtConstants.atPkamPrivateKey, atData);
    return true;
  }

  Future<bool> persistPublicKey(String publicKey) async {
    var atData = AtData();
    atData.data = publicKey.toString();
    await getLocalSecondary()!.keyStore!.put(
          AtConstants.atPkamPublicKey,
          atData,
        );
    return true;
  }

  Future<String?> getPrivateKey(String atSign) async {
    var privateKeyData = await getLocalSecondary()!.keyStore!.get(
          AtConstants.atPkamPrivateKey,
        );
    var privateKey = privateKeyData?.data;
    return privateKey;
  }

  @override
  Future<bool> delete(
    AtKey atKey, {
    bool isDedicated = false,
    DeleteRequestOptions? deleteRequestOptions,
  }) {
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.delete called', {"key": atKey}),
    );
    // ignore: no_leading_underscores_for_local_identifiers
    var _deleteResult = _delete(
      atKey,
      deleteRequestOptions: deleteRequestOptions,
    );
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.delete complete', {
        "key": atKey,
        "_deleteResult": _deleteResult,
      }),
    );
    return _deleteResult;
  }

  Future<bool> _delete(
    AtKey atKey, {
    DeleteRequestOptions? deleteRequestOptions,
  }) async {
    atKey.sharedBy ??= _atSign;
    // When namespace is not set in AtKey.namespace, default it to namespace from
    // AtClientPreferences
    if (atKey.metadata.namespaceAware) {
      atKey.namespace ??= preference?.namespace;
    }
    var builder = DeleteVerbBuilder()
      ..atKey = atKey
      ..noCommit = deleteRequestOptions?.noCommit ?? false;

    final prefForOp = SecondaryManager.getRemoteLocalPrefForOp(
      deleteRequestOptions?.useRemoteAtServer,
      preference?.remoteLocalPref,
    );
    _refuseNoCommitWithoutRemote(
        deleteRequestOptions?.noCommit ?? false, prefForOp);

    var deleteResult = await executeUpdateOrDelete(builder, prefForOp);

    return deleteResult != null;
  }

  /// Where a put goes: a `local:` key never leaves the device, and everything
  /// else is decided by the caller's preference. Extracted so the refusal
  /// below and the write itself cannot disagree about the answer.
  RemoteLocalPref _routingFor(
          AtKey atKey, bool? useRemoteAtServer) =>
      atKey.isLocal
          ? RemoteLocalPref.localOnly
          : SecondaryManager.getRemoteLocalPrefForOp(
              useRemoteAtServer, preference?.remoteLocalPref);

  /// Refuses a write that asks not to be recorded but is not going to the
  /// atServer.
  ///
  /// The flag is part of a command the atServer parses, and a local write
  /// sends no command: the record would take a local commit entry and sync
  /// would push it later under a command carrying no flag, so the commit would
  /// happen anyway. Doing nothing quietly is the worse outcome, because a
  /// caller cannot tell "not recorded" from "recorded after all".
  void _refuseNoCommitWithoutRemote(bool noCommit, RemoteLocalPref prefForOp) {
    if (noCommit && prefForOp != RemoteLocalPref.remoteOnly) {
      throw IllegalArgumentException(
          'noCommit asks the atServer not to record this operation, so the '
          'operation has to reach the atServer. Set useRemoteAtServer as '
          'well, or drop noCommit — as written it would silently record the '
          'commit it was asked to avoid.');
    }
  }

  Future<String?> executeUpdateOrDelete(
    VerbBuilder builder,
    RemoteLocalPref prefForOp,
  ) async {
    switch (prefForOp) {
      case RemoteLocalPref.localOnly:
        return await localSecondary!.executeVerb(builder, sync: true);
      case RemoteLocalPref.remoteOnly:
        return await _remoteSecondary!.executeVerb(builder);
    }
  }

  @override
  Future<AtValue> get(
    AtKey atKey, {
    bool isDedicated = false,
    GetRequestOptions? getRequestOptions,
  }) async {
    Secondary? secondary;
    try {
      // validate the get request.
      await AtClientValidation().validateAtKey(atKey);
      // Get the verb builder for the atKey
      var verbBuilder = GetRequestTransformer(
        this,
      ).transform(atKey, requestOptions: getRequestOptions);
      // Execute the verb.
      if (atKey.isLocal) {
        secondary = getLocalSecondary()!;
      } else {
        if (getRequestOptions?.useRemoteAtServer == true) {
          secondary = getRemoteSecondary()!;
        } else {
          secondary = SecondaryManager.getSecondary(
            this,
            verbBuilder,
            SecondaryManager.getRemoteLocalPrefForOp(
              getRequestOptions?.useRemoteAtServer,
              preference?.remoteLocalPref,
            ),
          );
        }
      }
      var getResponse = await secondary.executeVerb(verbBuilder);
      // Return empty value if getResponse is null.
      if (getResponse == null ||
          getResponse.isEmpty ||
          getResponse == 'data:null') {
        return AtValue();
      }
      // Send AtKey and AtResponse to transform the response to AtValue.
      var getResponseTuple = Tuple<AtKey, String>()
        ..one = atKey
        ..two = (getResponse);
      // Transform the response and return
      var atValue = await GetResponseTransformer(
        this,
      ).transform(getResponseTuple);
      return atValue;
    } on AtException catch (e) {
      var exceptionScenario = (secondary is LocalSecondary)
          ? ExceptionScenario.localVerbExecutionFailed
          : ExceptionScenario.remoteVerbExecutionFailed;
      e.stack(
        AtChainedException(Intent.fetchData, exceptionScenario, e.message),
      );
      throw AtExceptionManager.createException(e);
    }
  }

  @override
  Future<Metadata?> getMeta(AtKey atKey, {bool isDedicated = false}) async {
    var atValue = await get(atKey);
    return atValue.metadata;
  }

  @override
  Future<bool> keyExists(AtKey key, bool? useRemoteAtServer) async {
    String s = key.toString();
    final matches = await getKeys(
      regex: s,
      useRemoteAtServer: useRemoteAtServer,
    );
    return matches.contains(s);
  }

  @override
  Future<List<String>> getKeys({
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool showHiddenKeys = false,
    bool? useRemoteAtServer,
  }) async {
    var scanBuilder = ScanVerbBuilder()
      ..sharedWith = sharedWith
      ..sharedBy = sharedBy
      ..regex = regex
      ..showHiddenKeys = showHiddenKeys
      ..auth = true;
    Secondary secondary;
    if (useRemoteAtServer == true) {
      secondary = getRemoteSecondary()!;
    } else {
      secondary = SecondaryManager.getSecondary(
        this,
        scanBuilder,
        SecondaryManager.getRemoteLocalPrefForOp(
          useRemoteAtServer,
          preference?.remoteLocalPref,
        ),
      );
    }

    var scanResult = await secondary.executeVerb(scanBuilder);
    scanResult = _formatResult(scanResult);
    var result = [];
    if (scanResult.isNotEmpty) {
      result = List<String>.from(jsonDecode(scanResult));
    }
    return result as FutureOr<List<String>>;
  }

  @override
  Future<List<AtKey>> getAtKeys({
    String? regex,
    String? sharedBy,
    String? sharedWith,
    bool showHiddenKeys = false,
    bool? useRemoteAtServer,
  }) async {
    var getKeysResult = await getKeys(
      regex: regex,
      sharedBy: sharedBy,
      sharedWith: sharedWith,
      showHiddenKeys: showHiddenKeys,
      useRemoteAtServer: useRemoteAtServer,
    );
    var result = <AtKey>[];
    if (getKeysResult.isNotEmpty) {
      for (var key in getKeysResult) {
        try {
          result.add(AtKey.fromString(key));
        } on InvalidSyntaxException {
          _logger.severe('$key is not a well-formed key');
        } on Exception catch (e) {
          _logger.severe(
            'Exception occurred: ${e.toString()}. Unable to form key $key',
          );
        }
      }
    }
    return result;
  }

  @override
  Future<bool> put(
    AtKey atKey,
    dynamic value, {
    bool isDedicated = false,
    PutRequestOptions? putRequestOptions,
  }) async {
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.put called', {"key": atKey}),
    );
    // If the value is neither String nor List<int> throw exception
    if (value is! String && value is! List<int>) {
      throw AtValueException(
        'Invalid value type found ${value.runtimeType}. Expected String or List<int>',
      );
    }
    AtResponse atResponse = AtResponse();
    if (value is String) {
      atResponse = await putText(
        atKey,
        value,
        putRequestOptions: putRequestOptions,
      );
    }
    if (value is List<int>) {
      atResponse = await putBinary(
        atKey,
        value,
        putRequestOptions: putRequestOptions,
      );
    }
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.put complete', {"atKey": atKey}),
    );
    return atResponse.response.isNotEmpty;
  }

  /// Puts text data into the keystore.
  @override
  Future<AtResponse> putText(
    AtKey atKey,
    String value, {
    PutRequestOptions? putRequestOptions,
  }) async {
    try {
      // Setting metadata.isBinary to false for putText
      atKey.metadata.isBinary = false;
      return await _putInternal(atKey, value, putRequestOptions);
    } on AtException catch (e) {
      throw AtExceptionManager.createException(e);
    }
  }

  /// Puts binary data (e.g. images, files etc.) into the keystore.
  @override
  Future<AtResponse> putBinary(
    AtKey atKey,
    List<int> value, {
    PutRequestOptions? putRequestOptions,
  }) async {
    try {
      // Setting metadata.isBinary to true for putBinary
      atKey.metadata.isBinary = true;
      // Base2e15.encode method converts the List<int> type to String.
      return await _putInternal(
        atKey,
        Base2e15.encode(value),
        putRequestOptions,
      );
    } on AtException catch (e) {
      throw AtExceptionManager.createException(e);
    }
  }

  @visibleForTesting
  dynamic ensureLowerCase(AtKey atKey) {
    if (upperCaseRegex.hasMatch(atKey.key) ||
        (atKey.namespace != null &&
            upperCaseRegex.hasMatch(atKey.namespace!))) {
      _logger.finer(
        'AtKey: ${atKey.toString()} previously contained upper case'
        ' characters, AtKey has been converted to lower case',
      );
      //AtKey.toString() in the above log will convert the entire key to lower case
    }
  }

  Future<AtResponse> _putInternal(
    AtKey atKey,
    dynamic value,
    PutRequestOptions? putRequestOptions,
  ) async {
    // Refused before any work: the routing decision needs only the key and the
    // options, so doing the encryption first would reach the same answer more
    // slowly — and on a client with no local store it would not reach it at
    // all, dying on the missing secondary instead.
    _refuseNoCommitWithoutRemote(putRequestOptions?.noCommit ?? false,
        _routingFor(atKey, putRequestOptions?.useRemoteAtServer));
    // Performs the put request validations.
    AtClientValidation.validatePutRequest(atKey, value, preference!);
    // Set sharedBy to currentAtSign if not set.
    if (atKey.sharedBy.isNull) {
      atKey.sharedBy = _atSign;
    }
    if (atKey.metadata.namespaceAware) {
      atKey.namespace ??= preference?.namespace;
    }

    atKey.metadata.ivNonce ??= EncryptionUtil.generateIV();
    ensureLowerCase(atKey);

    // validate the atKey
    // * Setting the validateOwnership to true to perform KeyOwnerShip validation and KeyShare validation
    // * Setting enforceNamespace to true unless specifically set to false in the AtClientPreference
    bool enforceNamespace = true;
    // ignore: deprecated_member_use_from_same_package
    if (preference != null && preference!.enforceNamespace == false) {
      enforceNamespace = false;
    }
    // Clients should be able to store any local keys they want
    if (atKey.isLocal) {
      enforceNamespace = false;
    }
    var validationResult = AtKeyValidators.get().validate(
      atKey.toString(),
      ValidationContext()
        ..atSign = _atSign
        ..validateOwnership = true
        ..enforceNamespace = enforceNamespace,
    );
    // If the validationResult.isValid is false, validation of AtKey failed.
    // throw AtClientException with failure reason.
    if (!validationResult.isValid) {
      throw AtKeyException(validationResult.failureReason);
    }
    // Give the provider that will encrypt this write a chance to act before the
    // pipeline starts. The nskey data path needs it: minting a content key means
    // writing a conveyance record, and that cannot happen once the transformer
    // is mid-way through building a verb builder.
    // A `local:` record is excluded: [AtKey.isLocal] means it is never synced
    // to the atServer, and the keystore already encrypts it at rest. Routing
    // one through the shared-data pipeline bought nothing and cost it
    // correctness — every post-quantum provider declines a local key, so the
    // defaulted id fell back to legacy and every local write became a legacy
    // write, refused outright under `disallowLegacyEncryption`.
    var options = putRequestOptions ?? PutRequestTransformer.defaultOptions;
    if (!atKey.metadata.isPublic && !atKey.isLocal && options.shouldEncrypt) {
      try {
        await CryptoRuntime(this).prepareWrite(
          atKey,
          requestedProviderId: options.cryptoProviderId,
          // Any record the provider writes here is one this write will cite, so
          // it has to travel the same route this write does.
          useRemoteAtServer: options.useRemoteAtServer,
          // Not stamped here: the catch below may re-route this write to
          // legacy, and a key stamped with the provider that then declined
          // would claim a scheme its value was never sealed under.
          stampProviderId: false,
        );
      } on NamespaceKeyUnavailableException catch (e) {
        if (!mayFallBackToLegacy(_preference)) rethrow;
        // The destination has no post-quantum key, and this app has said it
        // would rather reach it under legacy than not at all. Nothing is in
        // flight yet — that is why the pre-pass raises this — so the write can
        // still be routed, and the transformer resolves the provider from these
        // options rather than from the preference.
        _logger.warning(
            'falling back to legacy encryption for ${atKey.key}: ${e.message}');
        options = _copyOptionsForLegacyFallback(options);
      }
    }

    var tuple = Tuple<AtKey, dynamic>()
      ..one = atKey
      ..two = value;

    //Get encryptionPrivateKey for public key to signData
    String? encryptionPrivateKey;
    if (atKey.metadata.isPublic == true) {
      encryptionPrivateKey = await localSecondary?.getEncryptionPrivateKey();
    }
    // Transform put request
    // Optionally passing encryption private key to sign the public data.
    UpdateVerbBuilder putBuilder = await putRequestTransformer.transform(
      tuple,
      encryptionPrivateKey: encryptionPrivateKey,
      // `options`, not `putRequestOptions`: a cold-start legacy fallback is
      // expressed by rewriting the options, and the transformer is where the
      // provider is finally selected.
      requestOptions: options,
    );
    // Validate the size of the value after encryption/encoding
    // Since AtClientPreference is mandatory argument in create method, _preference
    // will not be null.
    if (putBuilder.value.length > _preference!.maxDataSize) {
      throw BufferOverFlowException(
        'The length of value exceeds the maximum allowed length. Maximum buffer size is ${_preference!.maxDataSize} bytes. Found ${value.toString().length} bytes',
      );
    }

    var putResponse = await executeUpdateOrDelete(
        putBuilder, _routingFor(atKey, putRequestOptions?.useRemoteAtServer));

    // If putResponse is null or empty, return AtResponse with isError set to true
    if (putResponse == null || putResponse.isEmpty) {
      return AtResponse()..isError = true;
    }
    return await PutResponseTransformer().transform(putResponse);
  }

  @override
  Future<String> notifyStatus(String notificationId) async {
    var builder = NotifyStatusVerbBuilder()..notificationId = notificationId;
    var notifyStatus = await getRemoteSecondary()!.executeVerb(builder);
    return notifyStatus;
  }

  @override
  Future<String> notifyList({
    String? fromDate,
    String? toDate,
    String? regex,
    bool isDedicated = false,
  }) async {
    try {
      var builder = NotifyListVerbBuilder()
        ..fromDate = fromDate
        ..toDate = toDate
        ..regex = regex;
      var notifyList = await getRemoteSecondary()!.executeVerb(builder);
      return notifyList;
    } on AtLookUpException catch (e) {
      throw AtClientException(e.errorCode, e.errorMessage);
    }
  }

  @override
  Future<bool> putMeta(
    AtKey atKey, {
    PutRequestOptions? putRequestOptions,
  }) async {
    var builder = UpdateVerbBuilder();
    builder
      ..atKey = atKey
      ..operation = AtConstants.updateMeta;

    var updateMetaResult = await executeUpdateOrDelete(
      builder,
      SecondaryManager.getRemoteLocalPrefForOp(
        putRequestOptions?.useRemoteAtServer,
        preference?.remoteLocalPref,
      ),
    );
    return updateMetaResult != null;
  }

  String? getOperation(dynamic value, Metadata? data) {
    if (value != null && data == null) {
      return AtConstants.value;
    }
    // Verifies if any of the args are not null
    var isMetadataNotNull = AtClientUtil.isAnyNotNull(
      a1: data!.ttl,
      a2: data.ttb,
      a3: data.ttr,
      a4: data.ccd,
      a5: data.isBinary,
      a6: data.isEncrypted,
    );
    //If value is not null and metadata is not null, return UPDATE_ALL
    if (value != null && isMetadataNotNull) {
      return AtConstants.updateAll;
    }
    //If value is null and metadata is not null,
    if (value == null && isMetadataNotNull) {
      return AtConstants.updateMeta;
    }
    return null;
  }

  String _formatResult(String? commandResult) {
    var result = commandResult;
    if (result != null) {
      result = result.replaceFirst(RegExp('^data:'), '');
    }
    return result ??= '';
  }

  /// Resolves this client's PKAM signing algorithm from the enrollment's key
  /// material — the authoritative source; you cannot sign ML-DSA with an RSA
  /// key. A null resolution (a legacy flat-fields enrollment, or no keyfile
  /// source at all) leaves the preference's value as the fallback.
  Future<void> _resolveSigningAlgoFromKeyMaterial() async {
    final id = enrollmentId;
    if (_atKeysIo == null || id == null) return;
    try {
      final keys = await _atKeysIo!.read(_atSign);
      resolved_algo.recordResolvedSigningAlgo(
          this, keys.signingAlgorithmForEnrollment(id));
    } on Exception catch (e) {
      // Unresolved is survivable — connections fall back to the preference's
      // algorithm — but it must not be silent: under a typed enrollment that
      // fallback PKAMs with the wrong routine on every reconnect.
      _logger.warning(
          'Could not resolve the signing algorithm for enrollment $id from '
          'key material: $e. Connections will authenticate with the '
          // ignore: deprecated_member_use_from_same_package
          'preference value (${_preference?.signingAlgoType}).');
    }
  }

  /// Whether an enrollment authenticating with [held] must move to satisfy a
  /// posture asking for [wanted].
  ///
  /// **A posture is a floor, never a downgrade.** Key material wins, so a
  /// client built against an older at_client — or deliberately run at
  /// `PqPosture.legacy` — cannot un-retrofit an atSign that has already moved.
  /// `legacy` means "do not drive an upgrade", not "return to legacy".
  ///
  /// "Stronger" is at_chops' own total order rather than a judgement made
  /// here: a signer and a verifier that disagreed about it would negotiate
  /// against themselves.
  @visibleForTesting
  static bool retrofitIsDue(
          {required SigningAlgoType wanted, required SigningAlgoType held}) =>
      held != wanted && SigningAlgoType.strongestOf({wanted, held}) == wanted;

  /// What a client holding NO enrollment asks its first one to be.
  ///
  /// Nothing can be carried over: the client names no enrollment, so it has no
  /// record to read an app, a device or a grant from. So the constants name it,
  /// and it asks for everything — which is not an escalation, because the
  /// connection making the request has proved possession of the atSign's own
  /// root credential and is already unscoped, so there is nothing narrower to
  /// bound it by.
  ///
  /// ⛔ **The device name is per device, NOT the bare constant.** Sibling
  /// clones of one pre-enrollment keyfile each retrofit to their own
  /// enrollment, and the atServer refuses a request naming an
  /// `(appName, deviceName)` that an approved enrollment already holds. A
  /// shared constant would therefore let the FIRST device upgrade and leave
  /// every other one refused at every start, for ever, with nothing on the
  /// device saying why. Fresh per call rather than derived from anything, so a
  /// failed attempt's pending record cannot block the retry either.
  @visibleForTesting
  static ({String appName, String deviceName, Map<String, String> grants})
      firstEnrollmentIdentity() => (
            appName: firstEnrollmentAppName,
            deviceName: '$firstEnrollmentDeviceName-${Uuid().v4()}',
            grants: const {'*': 'rw', '__manage': 'rw'},
          );

  /// Settles the enrollment this client runs as, before anything that derives
  /// from it is built.
  ///
  /// A posture is a floor. When it asks for a stronger authentication key than
  /// the client's credential holds, the client retrofits itself and comes up on
  /// the new enrollment. Whether to retrofit is **derived from key material,
  /// never stored**: a stored flag would be a second control over one
  /// behaviour, and the derivation reproduces every cell of the posture matrix
  /// on its own. There is no preference opt-out.
  ///
  /// **A client holding NO enrollment is included, and its credential is the
  /// atSign's own.** A pre-enrollment atSign authenticates with the flat
  /// `at_pkam_publickey`, which at_lookup signs with rsa2048, so it compares
  /// as rsa2048 and a post-quantum posture moves it exactly as it moves a
  /// legacy enrollment. What differs is only where the new enrollment's name
  /// and grants come from — see [firstEnrollmentIdentity] — and that the
  /// atServer parks the request `pending` rather than auto-approving it,
  /// because that branch needs an APKAM-authenticated connection; at_auth
  /// approves it over the same connection.
  ///
  /// **Sequenced here rather than moved afterwards.** The monitor, the sync
  /// service's own `RemoteSecondary` and the encryption service are all built
  /// from this client's enrollment id *after* `_init` returns, so settling it
  /// first makes every one of them correct by construction. Retrofitting a
  /// live client instead would mean moving each of them underneath its holder,
  /// and a connection missed that way goes on working for the atServer's
  /// 720-hour grace — a half-moved client that looks healthy for a month and
  /// then fails with nothing pointing back here.
  ///
  /// Nothing is fatal — errors included, which is why there are two catch
  /// clauses. A client that cannot retrofit comes up on the credential it
  /// already had and tries again next start; `retrofitIdentity` is idempotent
  /// per keyfile, which is what makes every-start safe. The cost is paid once
  /// — the check below is local, so a client with nothing to do makes no round
  /// trip at all.
  Future<void> _settleEnrollmentIdentity() async {
    final id = enrollmentId;
    final keysIo = _atKeysIo;
    if (keysIo == null) return;
    final subject = id ?? 'this atSign\'s own keys';

    final wanted = _preference!.authenticationKeyAlgorithm;
    SigningAlgoType held;
    if (id == null) {
      // A PRE-ENROLLMENT atSign: it holds no enrollment at all and
      // authenticates with the flat `at_pkam_publickey`, which at_lookup signs
      // with rsa2048. So it compares as rsa2048 — and at a legacy posture,
      // where that is also what is wanted, the comparison below leaves it
      // exactly where it is.
      held = SigningAlgoType.rsa2048;
    } else {
      try {
        // A null resolution is not "unknown". `AtKeys.authenticationFor`
        // documents it as the flat fields' RSA keypair, and at_lookup signs
        // with `rsa2048` by default, so a legacy enrollment compares as
        // rsa2048 — which is precisely the enrollment a PQ posture exists to
        // move.
        held = (await keysIo.read(_atSign)).authenticationAlgorithmFor(id) ??
            SigningAlgoType.rsa2048;
      } on Exception catch (e) {
        _logger.warning('Could not read key material for enrollment $id, so '
            'whether a retrofit is due cannot be decided. Coming up on $id: $e');
        return;
      }
    }

    if (!retrofitIsDue(wanted: wanted, held: held)) return;

    _logger.info('$subject authenticates with ${held.name} and this '
        'posture requires ${wanted.name}; retrofitting');

    try {
      final String appName;
      final String deviceName;
      final Map<String, String> grants;
      if (id == null) {
        final first = firstEnrollmentIdentity();
        appName = first.appName;
        deviceName = first.deviceName;
        grants = first.grants;
      } else {
        // appName, deviceName and the grants come off the enrollment record
        // rather than the preference: the new enrollment reuses them verbatim,
        // because losing authority is a downgrade and would land silently, a
        // namespace at a time. There is no escalation to weigh — the atServer
        // refuses any grant the parent does not itself hold.
        final enrollment = await localSecondary?.getEnrollmentDetails();
        final recordApp = enrollment?.appName;
        final recordDevice = enrollment?.deviceName;
        if (enrollment == null || recordApp == null || recordDevice == null) {
          _logger.warning('Enrollment $id is due a retrofit, but its record '
              'does not name an app and device to carry over. Coming up on '
              '$id.');
          return;
        }
        appName = recordApp;
        deviceName = recordDevice;
        grants = (enrollment.namespace ?? const <String, dynamic>{})
            .map((namespace, access) => MapEntry(namespace, '$access'));
      }

      final newSession = await retrofitIdentity(
        session: AtAuthSession(
          atSign: _atSign,
          rootDomain:
              AtRootDomain(_preference!.rootDomain, _preference!.rootPort),
          atKeysIo: keysIo,
          namespace: _preference!.namespace,
          // Null for a pre-enrollment atSign, and at_auth reads exactly that
          // to decide it must approve its own request: the atServer's
          // self-enrolment auto-approve is reachable only from an
          // APKAM-authenticated connection.
          enrollmentId: id,
          // The retrofit submits on an already-authenticated connection, and
          // this one is authenticated as the enrollment being retrofitted —
          // or, with no enrollment, as the atSign itself.
          atLookUp: _remoteSecondary!.atLookUp,
        ),
        preference: _preference!,
        appName: appName,
        deviceName: deviceName,
        namespaces: grants,
      );

      final newId = newSession.enrollmentId;
      if (newId == null || newId == id) {
        _logger.warning('The retrofit of $subject returned no new enrollment '
            'id. Coming up on $subject.');
        return;
      }

      // Recorded before anything else, so a caller naming the id it captured
      // before this retrofit reaches THIS client rather than building a
      // duplicate of it.
      supersededInstanceKeys[instanceKey(_atSign, id)] =
          instanceKey(_atSign, newId);
      enrollmentId = newId;
      await _rederiveFromEnrollment(previousEnrollmentId: id);
      _logger
          .info('Retrofitted $subject to $newId; this client runs as $newId');
    } on Exception catch (e) {
      // The legacy credential is untouched by a failed retrofit — the atServer
      // caps a parent enrollment on success, never before, and it never
      // touches the flat PKAM key at all — so the client is fully usable.
      _logger.warning('The retrofit of $subject did not complete, so this '
          'client comes up on $subject and the next start will try again: $e');
    } on Error catch (e, stackTrace) {
      // Also not fatal, and a separate clause because it is a different
      // report: an Error names a defect — a key store that cannot read, a
      // seam left unwired — where an Exception names a condition the next
      // start may find changed. Both leave a usable client, which is this
      // method's whole contract, and an Error escaping would instead fail
      // CONSTRUCTION. That is reachable: `retrofitIdentity` refuses a session
      // with no AtLookUp by throwing `ArgumentError`, and an `AtKeysIo` is
      // free to throw `UnimplementedError` from `read`.
      _logger.severe('The retrofit of $subject failed with an error rather '
          'than an exception, which names a defect rather than a passing '
          'condition. This client comes up on $subject: $e\n$stackTrace');
    }
  }

  /// Rebuilds everything `_init` derives from the enrollment id, after it has
  /// changed. The old connection is closed explicitly: left open it stays
  /// authenticated as the superseded enrollment for the atServer's grace
  /// period.
  Future<void> _rederiveFromEnrollment(
      {required String? previousEnrollmentId}) async {
    await _resolveSigningAlgoFromKeyMaterial();
    _atChops = await _createAtChops(_atSign);

    final previous = _remoteSecondary;
    _remoteSecondary = buildRemoteSecondary();
    try {
      await previous?.atLookUp.close();
    } on Exception catch (e) {
      _logger.warning('The connection authenticated as '
          '${previousEnrollmentId ?? "the atSign itself"} could not be closed; '
          'it will idle out: $e');
    }
  }

  Future<AtChops> _createAtChops(String atSign) async {
    // When the client was handed an AtKeysIo *source* (and no live
    // AtChops/AtLookUp was injected by auth), derive our own PKAM+encryption
    // AtChops from that source instead of reading key material out of the local
    // secondary. This is what lets a freshly rebuilt connection PKAM on its own
    // socket — parity with the AtChops auth used to inject.
    if (_atKeysIo != null) {
      final keys = await _atKeysIo!.read(atSign);
      // A typed-material enrollment (a self-retrofit's) authenticates with
      // its own signing keypair and algorithm; the flat fields keep carrying
      // the original enrollment's RSA credentials, so reading them here
      // would sign PKAM with the wrong key under this client's enrollment
      // id. AtKeys decides which of the two this enrollment owns, off the
      // keyfile just read — the same resolver AtAuthImpl.authenticate uses.
      //
      // Not the algorithm _resolveSigningAlgoFromKeyMaterial recorded: that
      // records nothing when its own read throws, and it documents the
      // consequence as a preference fallback for the *algorithm*. Letting it
      // pick the keypair too turns a survivable failure into signing with a
      // key that is not this enrollment's.
      return keys.authenticationFor(enrollmentId).chops;
    }
    AtEncryptionKeyPair? atEncryptionKeyPair;
    AtPkamKeyPair? atPkamKeyPair;
    try {
      var encryptionPublicKey = await localSecondary!.getEncryptionPublicKey(
        atSign,
      );
      var encryptionPrivateKey =
          await localSecondary!.getEncryptionPrivateKey();
      if (encryptionPublicKey != null && encryptionPrivateKey != null) {
        atEncryptionKeyPair = AtEncryptionKeyPair.create(
          encryptionPublicKey,
          encryptionPrivateKey,
        );
      }
    } on KeyNotFoundException catch (e) {
      _logger.warning(
        '_createAtChops  - Exception while getting encryption key pair from local secondary: ${e.toString()}',
      );
    }
    try {
      var pkamPublicKey = await localSecondary!.getPkamPublicKey();
      var pkamPrivateKey = await localSecondary!.getPkamPrivateKey();

      if (pkamPublicKey != null && pkamPrivateKey != null) {
        atPkamKeyPair = AtPkamKeyPair.create(pkamPublicKey, pkamPrivateKey);
      }
    } on KeyNotFoundException catch (e) {
      _logger.warning(
        '_createAtChops  - Exception while getting pkam key pair from local secondary: ${e.toString()}',
      );
    }
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    AtChopsImpl chops = AtChopsImpl(atChopsKeys);
    return chops;
  }

  /// Whether a write to a destination with no post-quantum key may go out
  /// legacy instead of failing.
  ///
  /// Two switches, saying opposite things: `allowLegacyCryptoFallback` is
  /// "reach this recipient however you can", `disallowLegacyEncryption` is
  /// "never write legacy". The second wins. Refusing here, rather than letting
  /// the fallback route the write and be refused at encryption, keeps the error
  /// the one the caller can act on — the destination has no post-quantum key —
  /// instead of a refusal that names a scheme the caller never chose.
  @visibleForTesting
  static bool mayFallBackToLegacy(AtClientPreference? preference) =>
      CryptoRuntime.mayFallBackToLegacy(preference);

  /// [options] with the crypto provider pinned to legacy, leaving the caller's
  /// object untouched — it may be a shared instance, and one write's fallback
  /// must not become every later write's default.
  static PutRequestOptions _copyOptionsForLegacyFallback(
          PutRequestOptions options) =>
      PutRequestOptions()
        ..useRemoteAtServer = options.useRemoteAtServer
        ..shouldEncrypt = options.shouldEncrypt
        ..cryptoProviderId = legacyCryptoProviderId;

  /// Fails fast at construction if the configured default provider id can't be
  /// resolved — neither among `AtClientPreference.crypto.providers` nor the
  /// built-in legacy provider. Crypto resolution itself is done by
  /// [CryptoRuntime] against the live `preference.crypto`, so there is no
  /// per-client registry to populate.
  void _validateDefaultCryptoProvider() {
    final config = CryptoConfig.forClient(this);
    final id = config.defaultProviderId;
    if (config.lookup(id) == null && id != legacyCryptoProviderId) {
      throw CryptoProviderNotRegistered(
        'Default crypto provider "$id" is not registered. '
        'Add it to AtClientPreference.crypto.providers.',
      );
    }
  }

  @override
  @Deprecated("Obsolete, will be removed in v4")
  Future<AtStreamResponse> stream(
    String sharedWith,
    String filePath, {
    String? namespace,
  }) async {
    var streamResponse = AtStreamResponse();
    var streamId = Uuid().v4();
    var file = File(filePath);
    var data = file.readAsBytesSync();
    var fileName = basename(filePath);
    fileName = base64.encode(utf8.encode(fileName));
    var encryptedData = await _encryptionService!.encryptStream(
      data,
      sharedWith,
    );
    var command =
        'stream:init$sharedWith namespace:$namespace $streamId $fileName ${encryptedData.length}\n';
    _logger.finer('sending stream init:$command');
    // Its own connection, because it hands the socket raw bytes and then
    // closes it — but built the same way as the client's, so it authenticates
    // as the same enrollment with the same routine.
    var remoteSecondary = buildRemoteSecondary();
    var result = await remoteSecondary.executeCommand(command, auth: true);
    _logger.finer('ack message:$result');
    if (result != null && result.startsWith('stream:ack')) {
      result = result.replaceAll('stream:ack ', '');
      result = result.trim();
      _logger.finer('ack received for streamId:$streamId');
      remoteSecondary.atLookUp.connection!.getSocket().add(encryptedData);
      // `readResponse` rather than reaching through to the listener: this
      // path has already written the bytes to the socket itself, so it needs
      // the read half alone. The listener is not in at_lookup's barrel.
      var streamResult = await (remoteSecondary.atLookUp as AtLookupMuxable)
          .readResponse(
              maxWaitMilliSeconds: _preference!.outboundConnectionTimeout);
      if (streamResult.startsWith('stream:done')) {
        await remoteSecondary.atLookUp.connection!.close();
        streamResponse.status = AtStreamStatus.complete;
      }
    } else if (result != null && result.startsWith('error:')) {
      result = result.replaceFirst(RegExp('^error:'), '');
      streamResponse.errorCode = result.split('-')[0];
      streamResponse.errorMessage = result.split('-')[1];
      streamResponse.status = AtStreamStatus.error;
    } else {
      streamResponse.status = AtStreamStatus.noAck;
    }
    return streamResponse;
  }

  @override
  @Deprecated("Obsolete, will be removed in v4")
  Future<void> sendStreamAck(
    String streamId,
    String fileName,
    int fileLength,
    String senderAtSign,
    Function streamCompletionCallBack,
    Function streamReceiveCallBack,
  ) async {
    var handler = StreamNotificationHandler();
    handler.remoteSecondary = getRemoteSecondary();
    handler.localSecondary = getLocalSecondary();
    handler.preference = _preference;
    handler.encryptionService = _encryptionService;
    var notification = AtStreamNotification()
      ..streamId = streamId
      ..fileName = fileName
      ..currentAtSign = _atSign
      ..senderAtSign = senderAtSign
      ..fileLength = fileLength;
    _logger.info('Sending ack for stream notification:$notification');
    await handler.streamAck(
      notification,
      streamCompletionCallBack,
      streamReceiveCallBack,
    );
  }

  @override
  Future<Map<String, FileTransferObject>> uploadFile(
    List<File> files,
    List<String> sharedWithAtSigns,
  ) async {
    var encryptionKey = _encryptionService!.generateFileEncryptionKey();
    var key = TextConstants.fileTransferKey + Uuid().v4();
    var fileStatus = await _uploadFiles(key, files, encryptionKey);
    // ignore: prefer_interpolation_to_compose_strings
    var fileUrl = TextConstants.fileBinURL + 'archive/' + key + '/zip';

    return shareFiles(
      sharedWithAtSigns,
      key,
      fileUrl,
      encryptionKey,
      fileStatus,
    );
  }

  @override
  Future<Map<String, FileTransferObject>> shareFiles(
    List<String> sharedWithAtSigns,
    String key,
    String fileUrl,
    String encryptionKey,
    List<FileStatus> fileStatus, {
    DateTime? date,
  }) async {
    var result = <String, FileTransferObject>{};
    for (var sharedWithAtSign in sharedWithAtSigns) {
      var fileTransferObject = FileTransferObject(
        key,
        encryptionKey,
        fileUrl,
        sharedWithAtSign,
        fileStatus,
        date: date,
      );
      try {
        var atKey = AtKey()
          ..key = key
          ..sharedWith = sharedWithAtSign
          ..metadata = Metadata()
          ..metadata.ttr = -1
          // file transfer key will be deleted after 30 days
          ..metadata.ttl = 2592000000
          ..sharedBy = _atSign;

        var notificationResult = await notificationService.notify(
          NotificationParams.forUpdate(
            atKey,
            value: jsonEncode(fileTransferObject.toJson()),
          ),
        );

        if (notificationResult.notificationStatusEnum ==
            NotificationStatusEnum.delivered) {
          fileTransferObject.sharedStatus = true;
        } else {
          fileTransferObject.sharedStatus = false;
        }
      } on Exception catch (e) {
        fileTransferObject.sharedStatus = false;
        fileTransferObject.error = e.toString();
      }
      result[sharedWithAtSign] = fileTransferObject;
    }
    return result;
  }

  Future<List<FileStatus>> _uploadFiles(
    String transferId,
    List<File> files,
    String encryptionKey,
  ) async {
    var fileStatuses = <FileStatus>[];
    for (var file in files) {
      var fileStatus = FileStatus(
        fileName: file.path.split(Platform.pathSeparator).last,
        isUploaded: false,
        size: await file.length(),
      );
      try {
        final encryptedFile = await _encryptionService!.encryptFileInChunks(
          file,
          encryptionKey,
          _preference!.fileEncryptionChunkSize,
        );
        var response =
            await FileTransferService().uploadToFileBinWithStreamedRequest(
          encryptedFile,
          transferId,
          fileStatus.fileName!,
        );
        encryptedFile.deleteSync();
        if (response != null && response.statusCode == 201) {
          final responseStr = await response.stream.bytesToString();
          var responseMap = jsonDecode(responseStr);
          fileStatus.fileName = responseMap['file']['filename'];
          fileStatus.isUploaded = true;
        }

        // storing sent files in a a directory.
        if (preference?.downloadPath != null) {
          var sentFilesDirectory = await Directory(
            '${preference!.downloadPath!}${Platform.pathSeparator}sent-files',
          ).create();
          await File(file.path).copy(
            sentFilesDirectory.path +
                Platform.pathSeparator +
                (fileStatus.fileName ?? ''),
          );
        }
      } on Exception catch (e) {
        fileStatus.error = e.toString();
      }
      fileStatuses.add(fileStatus);
    }
    return fileStatuses;
  }

  @override
  Future<List<FileStatus>> reuploadFiles(
    List<File> files,
    FileTransferObject fileTransferObject,
  ) async {
    var response = await _uploadFiles(
      fileTransferObject.transferId,
      files,
      fileTransferObject.fileEncryptionKey,
    );
    return response;
  }

  @override
  Future<List<File>> downloadFile(
    String transferId,
    String sharedByAtSign, {
    String? downloadPath,
  }) async {
    downloadPath ??= preference!.downloadPath;
    if (downloadPath == null) {
      throw Exception('downloadPath not found');
    }
    var atKey = AtKey()
      ..key = transferId
      ..sharedBy = sharedByAtSign;
    var result = await get(atKey);
    FileTransferObject fileTransferObject;
    try {
      if (FileTransferObject.fromJson(jsonDecode(result.value)) == null) {
        _logger.severe("FileTransferObject is null");
        throw AtClientException(
          error_codes['AtClientException'],
          'FileTransferObject is null',
        );
      }
      fileTransferObject = FileTransferObject.fromJson(
        jsonDecode(result.value),
      )!;
    } on Exception catch (e) {
      throw Exception('json decode exception in download file ${e.toString()}');
    }
    var downloadedFiles = <File>[];
    var fileDownloadResponse = await FileTransferService().downloadFromFileBin(
      fileTransferObject,
      downloadPath,
    );
    if (fileDownloadResponse.isError) {
      throw Exception('download fail');
    }
    var encryptedFileList = Directory(
      fileDownloadResponse.filePath!,
    ).listSync();
    try {
      for (var encryptedFile in encryptedFileList) {
        var decryptedFile = await _encryptionService!.decryptFileInChunks(
          File(encryptedFile.path),
          fileTransferObject.fileEncryptionKey,
          _preference!.fileEncryptionChunkSize,
          ivBase64: fileTransferObject.ivBase64,
        );
        decryptedFile.copySync(
          downloadPath +
              Platform.pathSeparator +
              encryptedFile.path.split(Platform.pathSeparator).last,
        );
        downloadedFiles.add(
          File(
            downloadPath +
                Platform.pathSeparator +
                encryptedFile.path.split(Platform.pathSeparator).last,
          ),
        );
        decryptedFile.deleteSync();
      }
      // deleting temp directory
      Directory(fileDownloadResponse.filePath!).deleteSync(recursive: true);
      return downloadedFiles;
    } catch (e) {
      print('error in downloadFile: $e');
      return [];
    }
  }

  @override
  Future<AtResponse> setSPP(String spp, {Duration? expiry}) async {
    if (expiry == null) {
      _logger.shout(
        'WARNING: Setting SPP without an expiration'
        '- defaulting to ${AtClient.defaultSppExpiry}',
      );
      expiry = AtClient.defaultSppExpiry;
    }
    // SPP should be 6 characters PIN. Throw exception if its less
    // or more than 6 characters
    if (spp.length != 6) {
      throw InvalidPinException.message("$spp should be 6 characters");
    }
    // Validate the SPP. The SPP should contain only alphanumeric characters.
    // Any special characters or any characters other than alphanumeric characters
    // are not allowed. Throw an exception
    bool hasMatch = RegExp(r'[\W-]+').hasMatch(spp);
    if (hasMatch) {
      throw InvalidPinException.message("$spp is not a valid SPP");
    }
    String? otpVerbResponse;
    try {
      otpVerbResponse = await _remoteSecondary?.executeCommand(
        'otp:put:$spp:ttl:${expiry.inMilliseconds}\n',
        auth: true,
      );
    } on AtLookUpException catch (e) {
      throw AtClientException(e.errorCode, e.errorMessage);
    } on AtException catch (e) {
      throw AtClientException.message(e.message);
    }
    otpVerbResponse = otpVerbResponse?.replaceFirst(RegExp('^data:'), '');
    return AtResponse()..response = otpVerbResponse!;
  }

  @override
  Future<AtResponse> getOTP() async {
    String? otpVerbResponse;
    try {
      otpVerbResponse = await _remoteSecondary?.executeCommand(
        'otp:get\n',
        auth: true,
      );
    } on AtLookUpException catch (e) {
      throw AtClientException(e.errorCode, e.errorMessage);
    } on AtException catch (e) {
      throw AtClientException.message(e.message);
    }
    otpVerbResponse = otpVerbResponse?.replaceFirst(RegExp('^data:'), '');
    return AtResponse()..response = otpVerbResponse!;
  }

  @override
  String? getCurrentAtSign() => _atSign;

  @override
  AtClientPreference? getPreferences() {
    return _preference;
  }

  ///[Deprecated] Use [AtClient.notificationService]
  @override
  @Deprecated('Use AtClient.notificationService')
  Future<void> startMonitor(
    String privateKey,
    Function? notificationCallback, {
    String? regex,
  }) async {
    throw UnimplementedError('AtClient.startMonitor has been deprecated');
  }

  @override
  @Deprecated("Use NotificationService")
  Future<bool> notify(
    AtKey atKey,
    String value,
    OperationEnum operation, {
    MessageTypeEnum? messageType,
    PriorityEnum? priority,
    StrategyEnum? strategy,
    int? latestN,
    String? notifier = AtConstants.system,
    bool isDedicated = false,
  }) async {
    AtKeyValidators.get().validate(
      atKey.toString(),
      ValidationContext()
        ..atSign = _atSign
        ..validateOwnership = true,
    );
    final notificationParams = NotificationParams.forUpdate(
      atKey,
      value: value,
    );
    final notifyResult = await notificationService.notify(notificationParams);
    return notifyResult.notificationStatusEnum ==
        NotificationStatusEnum.delivered;
  }

  @override
  @Deprecated('Use NotificationService')
  Future<String> notifyAll(
    AtKey atKey,
    String value,
    OperationEnum operation, {
    bool isDedicated = false,
  }) async {
    var returnMap = {};
    var sharedWithList = jsonDecode(atKey.sharedWith!);
    for (var sharedWith in sharedWithList) {
      atKey.sharedWith = sharedWith;
      final notificationParams = NotificationParams.forUpdate(
        atKey,
        value: value,
      );
      final notifyResult = await notificationService.notify(notificationParams);
      returnMap.putIfAbsent(
        sharedWith,
        () => (notifyResult.notificationStatusEnum ==
            NotificationStatusEnum.delivered),
      );
    }
    return jsonEncode(returnMap);
  }

  @override

  ///[Deprecated] Use [NotificationService.notify]
  @Deprecated("Use [NotificationService.notify]")
  Future<String?> notifyChange(NotificationParams notificationParams) async {
    NotificationResult result = await notificationService.notify(
      notificationParams,
    );
    if (result.atClientException != null) {
      throw result.atClientException!;
    }
    return result.notificationID;
  }
}
