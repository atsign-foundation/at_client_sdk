import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/secondary.dart';
import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/compaction/at_commit_log_compaction.dart';
import 'package:at_client/src/crypto/legacy/legacy_crypto_scheme.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/manager/storage_manager.dart';
import 'package:at_client/src/preference/at_client_config.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/encryption_service.dart';
import 'package:at_client/src/service/file_transfer_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
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
  SecondaryKeyStore? _localSecondaryKeyStore;
  @visibleForTesting
  LocalSecondary? localSecondary;
  RemoteSecondary? _remoteSecondary;
  AtClientCommitLogCompaction? _atClientCommitLogCompaction;
  AtClientConfig? _atClientConfig;
  static final upperCaseRegex = RegExp(r'[A-Z]');

  PutRequestTransformer putRequestTransformer = PutRequestTransformer();

  AtClientCommitLogCompaction? get atClientCommitLogCompaction =>
      _atClientCommitLogCompaction;

  @override
  // ignore: override_on_non_overriding_member
  AtChops? _atChops;

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

  SyncService? _syncService;

  @override
  set syncService(SyncService syncService) {
    _syncService = syncService;
    _finalizer.attach(_syncService!, 'SyncService for $_atSign');
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
        _notificationService!, 'NotificationService for $_atSign');
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

  static late AtSignLogger _logger;

  @override
  String? enrollmentId;

  @visibleForTesting
  static final Map atClientInstanceMap = <String, AtClient>{};

  static final Finalizer<String> _finalizer = Finalizer((service) {
    _logger.finer('Outgoing $service has been garbage collected');
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
        _logger.warning(
          'cleanupOrphans on $namespace failed: $e\n$st',
        );
      }
    }
    return c;
  }

  static Future<AtClient> create(
      String currentAtSign, String? namespace, AtClientPreference preferences,
      {@Deprecated('no longer needed. will be removed in a future release')
      AtClientManager? atClientManager,
      RemoteSecondary? remoteSecondary,
      EncryptionService? encryptionService,
      SecondaryKeyStore? localSecondaryKeyStore,
      AtChops? atChops,
      AtLookUp? atLookUp,
      AtClientCommitLogCompaction? atClientCommitLogCompaction,
      AtClientConfig? atClientConfig,
      String? enrollmentId}) async {
    currentAtSign = AtUtils.fixAtSign(currentAtSign);

    // Fetch cached AtClientImpl for re-use, or create a new one and init it
    AtClientImpl? atClientImpl;
    if (atClientInstanceMap.containsKey(currentAtSign)) {
      atClientImpl = atClientInstanceMap[currentAtSign];
      await atClientImpl!.start();
    } else {
      atClientImpl = AtClientImpl._(currentAtSign, namespace, preferences,
          remoteSecondary: remoteSecondary,
          encryptionService: encryptionService,
          localSecondaryKeyStore: localSecondaryKeyStore,
          atChops: atChops,
          atLookUp: atLookUp,
          atClientCommitLogCompaction: atClientCommitLogCompaction,
          atClientConfig: atClientConfig,
          enrollmentId: enrollmentId);

      await atClientImpl._init(atLookUp: atLookUp);
    }

    atClientInstanceMap[currentAtSign] = atClientImpl;
    return atClientInstanceMap[currentAtSign];
  }

  AtClientImpl._(
    String theAtSign,
    String? namespace,
    AtClientPreference preference, {
    RemoteSecondary? remoteSecondary,
    EncryptionService? encryptionService,
    SecondaryKeyStore? localSecondaryKeyStore,
    AtChops? atChops,
    AtLookUp? atLookUp,
    AtClientCommitLogCompaction? atClientCommitLogCompaction,
    AtClientConfig? atClientConfig,
    this.enrollmentId,
  }) {
    _atSign = theAtSign.toAtsign();
    _logger = AtSignLogger('AtClientImpl ($_atSign)');
    _preference = preference;
    _preference?.namespace ??= namespace;
    _localSecondaryKeyStore = localSecondaryKeyStore;

    if (_localSecondaryKeyStore != null && !_preference!.isLocalStoreRequired) {
      throw IllegalArgumentException(
          'A SecondaryKeyStore was injected, but preference.isLocalStoreRequired is false');
    }

    _remoteSecondary = remoteSecondary;
    _encryptionService = encryptionService;
    _atChops = atChops;
    _atClientCommitLogCompaction = atClientCommitLogCompaction;
  }

  Future<void> _init({AtLookUp? atLookUp}) async {
    if (_preference!.isLocalStoreRequired) {
      if (_localSecondaryKeyStore == null) {
        var storageManager = StorageManager(preference);
        await storageManager.init(_atSign, preference!.keyStoreSecret);
      }

      localSecondary = LocalSecondary(
        this,
        keyStore: _localSecondaryKeyStore,
        onEvent: emitDataEvent,
      );
      _atChops ??= await _createAtChops(_atSign);
      _atChops!.schemes.register('legacy', LegacyCryptoScheme(this));

      // Wire the event-driven expiry timer to the data-events stream.
      // Re-arms on every keystore mutation; first arm uses the current
      // cache state (no-op when nothing has TTL).
      _expirySub = dataEvents.listen((_) {
        if (_expirySweepInFlight) return;
        _armExpiryTimer();
      });
      _armExpiryTimer();

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
      localSecondary?.seedAvailabilityFiredAsOf(DateTime.timestamp());
      _availableSub = dataEvents.listen((_) {
        if (_availableSweepInFlight) return;
        _armAvailableTimer();
      });
      _armAvailableTimer();
    }

    // Using ??= because we may be injecting a RemoteSecondary
    _remoteSecondary ??= RemoteSecondary(_atSign, _preference!,
        atChops: atChops,
        atLookUp: atLookUp,
        privateKey: _preference!.privateKey,
        enrollmentId: enrollmentId);

    // Using ??= because we may be injecting an EncryptionService
    _encryptionService ??= EncryptionService(_atSign);
    _encryptionService!.remoteSecondary = _remoteSecondary;
    _encryptionService!.localSecondary = localSecondary;

    putRequestTransformer.atClient = this;

    _cascadeSetTelemetryService();
  }

  /// Arms (or re-arms) the one-shot expiry [Timer] at the
  /// LocalSecondary's earliest pending expiration. No-op when the
  /// LocalSecondary's event cache reports no TTL'd keys.
  ///
  /// A timestamp in the past arms a `Duration.zero` timer that fires
  /// on the next microtask — effectively immediate.
  void _armExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final ls = localSecondary;
    if (ls == null) return;
    final when = ls.nextExpiryAt();
    if (when == null) return;
    final wait = when.difference(DateTime.timestamp());
    _expiryTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      _onExpiryFire,
    );
  }

  /// Drives one expiry sweep and re-arms the timer for the next.
  /// `_expirySweepInFlight` suppresses re-arms triggered by the
  /// sweep's own `DataDeleted` events; the single re-arm in `finally`
  /// picks up the post-sweep state, including any mid-sweep writes
  /// (the keystore's in-memory cache is updated synchronously inside
  /// each put before the corresponding [DataEvent] microtask runs).
  Future<void> _onExpiryFire() async {
    _expirySweepInFlight = true;
    try {
      await localSecondary?.deleteExpiredKeys();
    } catch (e, st) {
      _logger.warning('Expiry sweep failed: $e\n$st');
    } finally {
      _expirySweepInFlight = false;
      _armExpiryTimer();
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
  void _armAvailableTimer() {
    _availableTimer?.cancel();
    _availableTimer = null;
    final ls = localSecondary;
    if (ls == null) return;
    final when = ls.nextAvailableAt();
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
      for (final keyStr in ls.keysWithAvailableAtAtOrBefore(now)) {
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
          ls.dropAvailabilityCacheEntry(keyStr);
        } on Exception catch (e) {
          _logger.warning('availability sweep failed for $keyStr: $e');
        }
      }
    } catch (e, st) {
      _logger.warning('Availability sweep failed: $e\n$st');
    } finally {
      _availableSweepInFlight = false;
      _armAvailableTimer();
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
    await startCompactionJob();
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
      await stopCompactionJob();
    } catch (e) {
      _logger.warning('Error while stopping compaction job: $e');
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

  @override
  Future<void> startCompactionJob(
      {Duration? commitLogCompactionDuration}) async {
    commitLogCompactionDuration ??= Duration(
        minutes:
            AtClientConfig.getInstance().commitLogCompactionTimeIntervalInMins);
    AtCompactionJob atCompactionJob = AtCompactionJob(
        (await AtCommitLogManagerImpl.getInstance().getCommitLog(_atSign))!,
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(_atSign)!);

    _atClientCommitLogCompaction ??=
        AtClientCommitLogCompaction.create(_atSign, atCompactionJob);

    _atClientConfig ??= AtClientConfig.getInstance();

    if (!_atClientCommitLogCompaction!.isCompactionJobRunning()) {
      _atClientCommitLogCompaction!
          .scheduleCompaction(commitLogCompactionDuration.inMinutes);
    }
  }

  @override
  Future<void> stopCompactionJob() async {
    _logger.info('Stopping the commit log compaction job');
    await _atClientCommitLogCompaction?.stopCompactionJob();
  }

  /// Does nothing unless a telemetry service has been injected
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
  RemoteSecondary? getRemoteSecondary() {
    return _remoteSecondary;
  }

  @override
  void setPreferences(AtClientPreference preference) async {
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
    await getLocalSecondary()!
        .keyStore!
        .put(AtConstants.atPkamPublicKey, atData);
    return true;
  }

  Future<String?> getPrivateKey(String atSign) async {
    var privateKeyData =
        await getLocalSecondary()!.keyStore!.get(AtConstants.atPkamPrivateKey);
    var privateKey = privateKeyData?.data;
    return privateKey;
  }

  @override
  Future<bool> delete(AtKey atKey,
      {bool isDedicated = false, DeleteRequestOptions? deleteRequestOptions}) {
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.delete called', {"key": atKey}),
    );
    // ignore: no_leading_underscores_for_local_identifiers
    var _deleteResult =
        _delete(atKey, deleteRequestOptions: deleteRequestOptions);
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.delete complete',
          {"key": atKey, "_deleteResult": _deleteResult}),
    );
    return _deleteResult;
  }

  Future<bool> _delete(AtKey atKey,
      {DeleteRequestOptions? deleteRequestOptions}) async {
    atKey.sharedBy ??= _atSign;
    // When namespace is not set in AtKey.namespace, default it to namespace from
    // AtClientPreferences
    if (atKey.metadata.namespaceAware) {
      atKey.namespace ??= preference?.namespace;
    }
    var builder = DeleteVerbBuilder()..atKey = atKey;

    var deleteResult = await executeUpdateOrDelete(
        builder,
        SecondaryManager.getRemoteLocalPrefForOp(
          deleteRequestOptions?.useRemoteAtServer,
          preference?.remoteLocalPref,
        ));

    return deleteResult != null;
  }

  Future<String?> executeUpdateOrDelete(
      VerbBuilder builder, RemoteLocalPref prefForOp) async {
    switch (prefForOp) {
      case RemoteLocalPref.localOnly:
        return await localSecondary!.executeVerb(builder, sync: true);
      case RemoteLocalPref.remoteOnly:
        return await _remoteSecondary!.executeVerb(builder);
    }
  }

  @override
  Future<AtValue> get(AtKey atKey,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions}) async {
    Secondary? secondary;
    try {
      // validate the get request.
      await AtClientValidation().validateAtKey(atKey);
      // Get the verb builder for the atKey
      var verbBuilder = GetRequestTransformer(this)
          .transform(atKey, requestOptions: getRequestOptions);
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
              ));
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
      var atValue =
          await GetResponseTransformer(this).transform(getResponseTuple);
      return atValue;
    } on AtException catch (e) {
      var exceptionScenario = (secondary is LocalSecondary)
          ? ExceptionScenario.localVerbExecutionFailed
          : ExceptionScenario.remoteVerbExecutionFailed;
      e.stack(
          AtChainedException(Intent.fetchData, exceptionScenario, e.message));
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
          ));
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
              'Exception occurred: ${e.toString()}. Unable to form key $key');
        }
      }
    }
    return result;
  }

  @override
  Future<bool> put(AtKey atKey, dynamic value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.put called', {"key": atKey}),
    );
    // If the value is neither String nor List<int> throw exception
    if (value is! String && value is! List<int>) {
      throw AtValueException(
          'Invalid value type found ${value.runtimeType}. Expected String or List<int>');
    }
    AtResponse atResponse = AtResponse();
    if (value is String) {
      atResponse =
          await putText(atKey, value, putRequestOptions: putRequestOptions);
    }
    if (value is List<int>) {
      atResponse =
          await putBinary(atKey, value, putRequestOptions: putRequestOptions);
    }
    _telemetry?.controller.sink.add(
      // ignore: experimental_member_use
      AtTelemetryEvent('AtClient.put complete', {"atKey": atKey}),
    );
    return atResponse.response.isNotEmpty;
  }

  /// Puts text data into the keystore.
  @override
  Future<AtResponse> putText(AtKey atKey, String value,
      {PutRequestOptions? putRequestOptions}) async {
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
  Future<AtResponse> putBinary(AtKey atKey, List<int> value,
      {PutRequestOptions? putRequestOptions}) async {
    try {
      // Setting metadata.isBinary to true for putBinary
      atKey.metadata.isBinary = true;
      // Base2e15.encode method converts the List<int> type to String.
      return await _putInternal(
          atKey, Base2e15.encode(value), putRequestOptions);
    } on AtException catch (e) {
      throw AtExceptionManager.createException(e);
    }
  }

  @visibleForTesting
  dynamic ensureLowerCase(AtKey atKey) {
    if (upperCaseRegex.hasMatch(atKey.key) ||
        (atKey.namespace != null &&
            upperCaseRegex.hasMatch(atKey.namespace!))) {
      _logger.finer('AtKey: ${atKey.toString()} previously contained upper case'
          ' characters, AtKey has been converted to lower case');
      //AtKey.toString() in the above log will convert the entire key to lower case
    }
  }

  Future<AtResponse> _putInternal(
      AtKey atKey, dynamic value, PutRequestOptions? putRequestOptions) async {
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
          ..enforceNamespace = enforceNamespace);
    // If the validationResult.isValid is false, validation of AtKey failed.
    // throw AtClientException with failure reason.
    if (!validationResult.isValid) {
      throw AtKeyException(validationResult.failureReason);
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
    UpdateVerbBuilder putBuilder = await putRequestTransformer.transform(tuple,
        encryptionPrivateKey: encryptionPrivateKey,
        requestOptions: putRequestOptions);
    // Validate the size of the value after encryption/encoding
    // Since AtClientPreference is mandatory argument in create method, _preference
    // will not be null.
    if (putBuilder.value.length > _preference!.maxDataSize) {
      throw BufferOverFlowException(
          'The length of value exceeds the maximum allowed length. Maximum buffer size is ${_preference!.maxDataSize} bytes. Found ${value.toString().length} bytes');
    }

    RemoteLocalPref remoteLocalPref;
    if (atKey.isLocal) {
      remoteLocalPref = RemoteLocalPref.localOnly;
    } else {
      remoteLocalPref = SecondaryManager.getRemoteLocalPrefForOp(
        putRequestOptions?.useRemoteAtServer,
        preference?.remoteLocalPref,
      );
    }
    var putResponse = await executeUpdateOrDelete(putBuilder, remoteLocalPref);

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
  Future<String> notifyList(
      {String? fromDate,
      String? toDate,
      String? regex,
      bool isDedicated = false}) async {
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
  Future<bool> putMeta(AtKey atKey,
      {PutRequestOptions? putRequestOptions}) async {
    var builder = UpdateVerbBuilder();
    builder
      ..atKey = atKey
      ..operation = AtConstants.updateMeta;

    var updateMetaResult = await executeUpdateOrDelete(
        builder,
        SecondaryManager.getRemoteLocalPrefForOp(
          putRequestOptions?.useRemoteAtServer,
          preference?.remoteLocalPref,
        ));
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
        a6: data.isEncrypted);
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

  Future<AtChops> _createAtChops(String atSign) async {
    AtEncryptionKeyPair? atEncryptionKeyPair;
    AtPkamKeyPair? atPkamKeyPair;
    try {
      var encryptionPublicKey =
          await localSecondary!.getEncryptionPublicKey(atSign);
      var encryptionPrivateKey =
          await localSecondary!.getEncryptionPrivateKey();
      if (encryptionPublicKey != null && encryptionPrivateKey != null) {
        atEncryptionKeyPair = AtEncryptionKeyPair.create(
            encryptionPublicKey, encryptionPrivateKey);
      }
    } on KeyNotFoundException catch (e) {
      _logger.warning(
          '_createAtChops  - Exception while getting encryption key pair from local secondary: ${e.toString()}');
    }
    try {
      var pkamPublicKey = await localSecondary!.getPkamPublicKey();
      var pkamPrivateKey = await localSecondary!.getPkamPrivateKey();

      if (pkamPublicKey != null && pkamPrivateKey != null) {
        atPkamKeyPair = AtPkamKeyPair.create(pkamPublicKey, pkamPrivateKey);
      }
    } on KeyNotFoundException catch (e) {
      _logger.warning(
          '_createAtChops  - Exception while getting pkam key pair from local secondary: ${e.toString()}');
    }
    final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    AtChopsImpl chops = AtChopsImpl(atChopsKeys);
    chops.schemes.register('legacy', LegacyCryptoScheme(this));
    return chops;
  }

  @override
  @Deprecated("Obsolete, will be removed in v4")
  Future<AtStreamResponse> stream(String sharedWith, String filePath,
      {String? namespace}) async {
    var streamResponse = AtStreamResponse();
    var streamId = Uuid().v4();
    var file = File(filePath);
    var data = file.readAsBytesSync();
    var fileName = basename(filePath);
    fileName = base64.encode(utf8.encode(fileName));
    var encryptedData =
        await _encryptionService!.encryptStream(data, sharedWith);
    var command =
        'stream:init$sharedWith namespace:$namespace $streamId $fileName ${encryptedData.length}\n';
    _logger.finer('sending stream init:$command');
    var remoteSecondary =
        RemoteSecondary(_atSign, _preference!, atChops: atChops);
    var result = await remoteSecondary.executeCommand(command, auth: true);
    _logger.finer('ack message:$result');
    if (result != null && result.startsWith('stream:ack')) {
      result = result.replaceAll('stream:ack ', '');
      result = result.trim();
      _logger.finer('ack received for streamId:$streamId');
      remoteSecondary.atLookUp.connection!.getSocket().add(encryptedData);
      var streamResult = await (remoteSecondary.atLookUp as AtLookupImpl)
          .messageListener
          .read(maxWaitMilliSeconds: _preference!.outboundConnectionTimeout);
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
      Function streamReceiveCallBack) async {
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
        notification, streamCompletionCallBack, streamReceiveCallBack);
  }

  @override
  Future<Map<String, FileTransferObject>> uploadFile(
      List<File> files, List<String> sharedWithAtSigns) async {
    var encryptionKey = _encryptionService!.generateFileEncryptionKey();
    var key = TextConstants.fileTransferKey + Uuid().v4();
    var fileStatus = await _uploadFiles(key, files, encryptionKey);
    // ignore: prefer_interpolation_to_compose_strings
    var fileUrl = TextConstants.fileBinURL + 'archive/' + key + '/zip';

    return shareFiles(
        sharedWithAtSigns, key, fileUrl, encryptionKey, fileStatus);
  }

  @override
  Future<Map<String, FileTransferObject>> shareFiles(
      List<String> sharedWithAtSigns,
      String key,
      String fileUrl,
      String encryptionKey,
      List<FileStatus> fileStatus,
      {DateTime? date}) async {
    var result = <String, FileTransferObject>{};
    for (var sharedWithAtSign in sharedWithAtSigns) {
      var fileTransferObject = FileTransferObject(
          key, encryptionKey, fileUrl, sharedWithAtSign, fileStatus,
          date: date);
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
      String transferId, List<File> files, String encryptionKey) async {
    var fileStatuses = <FileStatus>[];
    for (var file in files) {
      var fileStatus = FileStatus(
        fileName: file.path.split(Platform.pathSeparator).last,
        isUploaded: false,
        size: await file.length(),
      );
      try {
        final encryptedFile = await _encryptionService!.encryptFileInChunks(
            file, encryptionKey, _preference!.fileEncryptionChunkSize);
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
                  '${preference!.downloadPath!}${Platform.pathSeparator}sent-files')
              .create();
          await File(file.path).copy(sentFilesDirectory.path +
              Platform.pathSeparator +
              (fileStatus.fileName ?? ''));
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
      List<File> files, FileTransferObject fileTransferObject) async {
    var response = await _uploadFiles(fileTransferObject.transferId, files,
        fileTransferObject.fileEncryptionKey);
    return response;
  }

  @override
  Future<List<File>> downloadFile(String transferId, String sharedByAtSign,
      {String? downloadPath}) async {
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
            error_codes['AtClientException'], 'FileTransferObject is null');
      }
      fileTransferObject =
          FileTransferObject.fromJson(jsonDecode(result.value))!;
    } on Exception catch (e) {
      throw Exception('json decode exception in download file ${e.toString()}');
    }
    var downloadedFiles = <File>[];
    var fileDownloadResponse = await FileTransferService()
        .downloadFromFileBin(fileTransferObject, downloadPath);
    if (fileDownloadResponse.isError) {
      throw Exception('download fail');
    }
    var encryptedFileList =
        Directory(fileDownloadResponse.filePath!).listSync();
    try {
      for (var encryptedFile in encryptedFileList) {
        var decryptedFile = await _encryptionService!.decryptFileInChunks(
            File(encryptedFile.path),
            fileTransferObject.fileEncryptionKey,
            _preference!.fileEncryptionChunkSize,
            ivBase64: fileTransferObject.ivBase64);
        decryptedFile.copySync(downloadPath +
            Platform.pathSeparator +
            encryptedFile.path.split(Platform.pathSeparator).last);
        downloadedFiles.add(File(downloadPath +
            Platform.pathSeparator +
            encryptedFile.path.split(Platform.pathSeparator).last));
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
      _logger.shout('WARNING: Setting SPP without an expiration'
          '- defaulting to ${AtClient.defaultSppExpiry}');
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
          auth: true);
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
      otpVerbResponse =
          await _remoteSecondary?.executeCommand('otp:get\n', auth: true);
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
  Future<void> startMonitor(String privateKey, Function? notificationCallback,
      {String? regex}) async {
    throw UnimplementedError('AtClient.startMonitor has been deprecated');
  }

  @override
  @Deprecated("Use NotificationService")
  Future<bool> notify(AtKey atKey, String value, OperationEnum operation,
      {MessageTypeEnum? messageType,
      PriorityEnum? priority,
      StrategyEnum? strategy,
      int? latestN,
      String? notifier = AtConstants.system,
      bool isDedicated = false}) async {
    AtKeyValidators.get().validate(
        atKey.toString(),
        ValidationContext()
          ..atSign = _atSign
          ..validateOwnership = true);
    final notificationParams =
        NotificationParams.forUpdate(atKey, value: value);
    final notifyResult = await notificationService.notify(notificationParams);
    return notifyResult.notificationStatusEnum ==
        NotificationStatusEnum.delivered;
  }

  @override
  @Deprecated('Use NotificationService')
  Future<String> notifyAll(AtKey atKey, String value, OperationEnum operation,
      {bool isDedicated = false}) async {
    var returnMap = {};
    var sharedWithList = jsonDecode(atKey.sharedWith!);
    for (var sharedWith in sharedWithList) {
      atKey.sharedWith = sharedWith;
      final notificationParams =
          NotificationParams.forUpdate(atKey, value: value);
      final notifyResult = await notificationService.notify(notificationParams);
      returnMap.putIfAbsent(
          sharedWith,
          () => (notifyResult.notificationStatusEnum ==
              NotificationStatusEnum.delivered));
    }
    return jsonEncode(returnMap);
  }

  @override

  ///[Deprecated] Use [NotificationService.notify]
  @Deprecated("Use [NotificationService.notify]")
  Future<String?> notifyChange(NotificationParams notificationParams) async {
    NotificationResult result =
        await notificationService.notify(notificationParams);
    if (result.atClientException != null) {
      throw result.atClientException!;
    }
    return result.notificationID;
  }
}
