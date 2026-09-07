import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/secondary_address_finder_source.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/enrollment_service.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

/// Factory class for creating [AtClient], [SyncService] and [NotificationService] instances
///
/// Usage
/// ```
/// final atClientManager = AtClientManager.getInstance().setCurrentAtSign(<current_atsign>, <app_namespace>, <preferences>)
/// Apps have to call the above method again while switching atsign.
/// ```
/// atClientManager.atClient - for at client method calls
/// atClientManager.syncService - for invoking sync. Refer [SyncService] for detailed usage
/// atClientManager.notificationService - for notification methods. Refer [NotificationService] for detailed usage
class AtClientManager {
  final AtSignLogger _logger = AtSignLogger('AtClientManager');

  late String _atSign;
  AtClient? _currentAtClient;

  AtClient get atClient {
    if (_currentAtClient == null) {
      throw StateError('No atClient yet');
    } else {
      return _currentAtClient!;
    }
  }

  @Deprecated('Use atClientManager.atClient.syncService')
  SyncService get syncService => atClient.syncService;

  @Deprecated('Use atClientManager.atClient.notificationService')
  NotificationService get notificationService => atClient.notificationService;

  SecondaryAddressFinder? secondaryAddressFinder;
  final _changeListeners = <AtSignChangeListener>[];

  static final AtClientManager _singleton = AtClientManager._internal();

  AtClientManager._internal() {
    _registerAddressFinderSource();
  }

  factory AtClientManager.getInstance() {
    return _singleton;
  }

  // ignore: no_leading_underscores_for_local_identifiers
  AtClientManager(this._atSign) {
    _registerAddressFinderSource();
  }

  /// Points `RemoteSecondary`'s process-wide finder source at the singleton
  /// manager's field — the reach-up it has always performed, now behind a
  /// seam so it does not import this class. Registered by every constructor
  /// (idempotently — the closure is the same either way) so the source
  /// exists as soon as any manager does.
  static void _registerAddressFinderSource() {
    registerSecondaryAddressFinderSource(
        () => AtClientManager.getInstance().secondaryAddressFinder);
  }

  void setSecondaryAddressFinder(
      {SecondaryAddressFinder? secondaryAddressFinder}) {
    if (secondaryAddressFinder != null) {
      this.secondaryAddressFinder = secondaryAddressFinder;
    }
  }

  /// Switches the active atSign and (re)creates its associated services.
  ///
  /// The outgoing client is stopped via [AtClient.stop], which UNFILES it and
  /// releases its storage. ⚠️ It is not resumable: `start()` refuses a client
  /// whose storage was released, and nothing is left in the cache to resume.
  /// Calling this method again for the same atSign therefore builds a new
  /// client rather than reviving the old one.
  ///
  /// Use [AtClient.stop] only when permanently finished with an atSign (e.g.,
  /// logout or app shutdown).
  ///
  /// ⚠️ **A call naming the atSign that is already current usually recreates
  /// nothing.** When no [atChops], [atKeysIo], [atLookUp] or [enrollmentId]
  /// override is supplied and the current client is not stopped, this returns
  /// that client as it stands. That is deliberate: the stop-and-recreate path
  /// would briefly run two sync services against one Hive store. But it means
  /// that of [preference], only `crypto` is adopted — a caller changing
  /// anything else and expecting it to take effect gets nothing, silently. The
  /// The one exception is a changed rollout axis, which is refused outright
  /// rather than dropped, because it could not be honoured and would otherwise
  /// leave the caller running under a stage it thinks it has left.
  ///
  /// ⚠️ A changed `hiveStoragePath` is among the SILENT ones. It was refused
  /// until the per-location storage guard replaced that check, and the guard
  /// only fires where a store is opened — which a cached client does not do. A
  /// caller that names a different location and is handed the running client
  /// keeps the location that client already has.
  ///
  /// With [atKeysIo] the enrollment is the keys' own answer,
  /// `AtKeys.enrollmentToAuthenticateAs`; an [enrollmentId] that disagrees is
  /// logged at shout level and ignored.
  ///
  /// * [serviceFactory] - Overrides service creation (primarily for testing).
  /// * [atChops] - Shared crypto context for the new services.
  Future<AtClientManager> setCurrentAtSign(
      String atSign, String? namespace, AtClientPreference preference,
      {AtServiceFactory? serviceFactory,
      AtChops? atChops,
      AtKeysIo? atKeysIo,
      AtLookUp? atLookUp,
      String? enrollmentId,
      AtClientStorage? storage,

      /// The incoming client authenticates as a different enrollment of
      /// [atSign] than the outgoing one, over the same store, which is handed
      /// over open for the incoming client to close.
      bool principalChange = false}) async {
    serviceFactory ??= DefaultAtServiceFactory();

    _logger.finer("setCurrentAtSign called with atSign $atSign");
    AtUtils.fixAtSign(atSign);
    secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
        preference.rootDomain, preference.rootPort);

    // Idempotency: if the caller is asking for the SAME atSign that's
    // already current (with no caller-supplied override for atChops /
    // atLookUp / enrollmentId), short-circuit. The stop+recreate path
    // below is destructive: it stops the existing syncService and
    // builds a fresh one against the same Hive store, producing a
    // brief window where TWO syncService instances are alive against
    // the same on-disk queue. If a user write enqueues during that
    // window, the push can fire on the about-to-be-stopped sibling
    // (whose progress-listener list is empty after its `stop()` ran),
    // making the write invisible to any listener attached to the new
    // syncService — observed in CI as `bypasscache_test` timing out
    // with no `localToRemote` event.
    //
    // Callers needing a forced reset for a SAME-atSign change of
    // preferences / atChops / enrollmentId still get one — we only
    // skip when nothing in the request changed.
    //
    // Re-offering the storage the current client already holds is not a
    // change either: it is what a caller that owns one bundle for the whole
    // of its work does on every call, and rebuilding on it would tear the
    // client down for nothing.
    //
    // A principal change is never a no-op: the incoming client is a different
    // enrollment by definition, so it always takes the switch below.
    final currentAtSign = _currentAtClient?.getCurrentAtSign();
    if (currentAtSign != null &&
        currentAtSign == atSign &&
        !principalChange &&
        atChops == null &&
        atKeysIo == null &&
        atLookUp == null &&
        enrollmentId == null &&
        _storageIsUnchanged(storage) &&
        _currentAtClient!.isStopped == false) {
      // The full stop/recreate path below recreates via AtClientImpl.create(),
      // which adopts the supplied preference's crypto config onto a re-used
      // cached client. The short-circuit skips create(), so adopt it here too —
      // otherwise a same-atSign call carrying a new crypto config silently drops
      // it, surfacing as CryptoProviderNotRegistered on the next put.
      //
      // And for the same reason it must apply create()'s refusal: this path
      // returns a client that already exists, so a preference naming different
      // rollout axes is being dropped rather than applied. Skipping the check
      // here would put it on the path a caller reaches only with an override
      // argument, and leave the ordinary one silent.
      final existing = _currentAtClient;
      if (existing is AtClientImpl) {
        AtClientImpl.refuseChangedRolloutAxes(
            running: existing.getPreferences(),
            asked: preference,
            cacheKey: AtClientImpl.instanceKey(atSign, existing.enrollmentId));
        existing.getPreferences()?.crypto = preference.crypto;
      }
      _logger
          .info('setCurrentAtSign: already on $atSign with no override args; '
              'returning existing atClient (no stop/recreate).');
      return this;
    }

    _logger.info(
        'Switching atSigns ${_currentAtClient?.getCurrentAtSign()} -> $atSign');

    // Stop the outgoing atsign
    _atSign = atSign;
    final previousAtClient = _currentAtClient;
    // A principal change is a SUCCESSION: one enrollment of this atSign replaced
    // by another over the same store, usually an rsa2048-auth enrollment
    // succeeded by an mldsa65-auth one. Two enrollments that are both live get
    // separate stores instead; here the atServer retires the old one, so the
    // data follows. The bundle therefore crosses the switch OPEN — a plain
    // stop() closes a store the outgoing client built or was told to close —
    // and the store has to be told, because `attach` refuses a holder whose
    // principal differs from the last one. Carried from the outgoing client
    // when the caller named none, or named the one it holds: this is the one
    // place that knows which client is being replaced.
    final AtClientStorage? carried;
    if (principalChange &&
        previousAtClient is AtClientImpl &&
        (storage == null || storage.isHeldBy(previousAtClient))) {
      carried = await previousAtClient.stopHandingOverStorage();
    } else {
      await previousAtClient?.stop();
      carried = storage;
    }
    // Between holders, never under one: `forgetPrincipal` throws while a client
    // is attached, which is why it follows the stop.
    if (principalChange) await carried?.forgetPrincipal();

    // Spin up the new atClient
    _currentAtClient = await serviceFactory.atClient(
        _atSign, namespace, preference, this,
        atChops: atChops,
        atKeysIo: atKeysIo,
        atLookUp: atLookUp,
        enrollmentId: enrollmentId,
        storage: carried);

    var notificationService = await serviceFactory.notificationService(
        _currentAtClient!, this,
        secondaryAddressFinder: secondaryAddressFinder);
    _currentAtClient!.notificationService = notificationService;

    var syncService = await serviceFactory.syncService(
        _currentAtClient!, this, notificationService);
    _currentAtClient!.syncService = syncService;
    // Do NOT call `syncService.sync()` here: `SyncServiceImpl.create()`
    // already enqueues a one-shot warm-start sync request internally
    // (see its `warmStartSync` parameter). A second sync at startup
    // races the e2e harness — the first round can emit
    // `SyncStatus.success` with no work to do and let the listener
    // exit before the second round pulls the cross-server-notify
    // entries that haven't yet arrived on the local atServer.
    //
    // TODO Clean up for the above; shouldn't matter when or how often
    // code calls `sync()`

    EnrollmentService enrollmentService =
        serviceFactory.enrollmentService(_currentAtClient!);
    _currentAtClient!.enrollmentService = enrollmentService;

    // notify the subscribed listeners about atsign switch
    if (!identical(previousAtClient?.getCurrentAtSign(),
        _currentAtClient?.getCurrentAtSign())) {
      final switchAtSignEvent =
          SwitchAtSignEvent(previousAtClient, _currentAtClient!);
      _notifyListeners(switchAtSignEvent);
    }

    _logger.finer("setCurrentAtSign complete");

    return this;
  }

  /// Whether [storage] would leave the current client's storage as it is:
  /// either none was offered, or it is the object that client already holds.
  bool _storageIsUnchanged(AtClientStorage? storage) {
    if (storage == null) return true;
    final current = _currentAtClient;
    return current != null && storage.isHeldBy(current);
  }

  /// Explicit, typed hand-off from auth to client.
  ///
  /// Consumes an [AtAuthSession] (the key *source* + confirmed params) and lets
  /// the client rebuild its own connection: [session.atKeysIo] flows to
  /// `AtClientImpl.create(atKeysIo:)`, which derives its own PKAM [AtChops] and
  /// opens a fresh socket that PKAMs itself. Costs one extra PKAM handshake at
  /// startup — the accepted price of clean auth/client separation.
  ///
  /// Set [reuse] to adopt auth's already-authenticated connection
  /// ([session.atLookUp]) and skip the second handshake — the perf escape hatch.
  /// When false (default) the client opens its own fresh socket.
  ///
  /// [storage] is borrowed unless it was built with `closedByClient: true`, in
  /// which case the client closes it on [AtClient.stop]. Same rule as on
  /// [setCurrentAtSign].
  Future<AtClientManager> fromAuthSession(
      AtAuthSession session, AtClientPreference preference,
      {AtServiceFactory? serviceFactory,
      bool reuse = false,
      AtClientStorage? storage,
      bool principalChange = false}) async {
    // Destructure rootDomain onto the preference for now. A follow-up will add
    // an AtRootDomain-typed accessor to AtClientPreference so this can stop.
    preference.rootDomain = session.rootDomain.rootDomain;
    preference.rootPort = session.rootDomain.rootPort;

    if (reuse && session.atLookUp == null) {
      _logger.warning('fromAuthSession(reuse: true) but the session carries no '
          'authenticated AtLookUp; opening a fresh connection instead.');
    }

    return setCurrentAtSign(session.atSign, session.namespace, preference,
        serviceFactory: serviceFactory,
        atKeysIo: session.atKeysIo,
        atLookUp: reuse ? session.atLookUp : null,
        enrollmentId: session.enrollmentId,
        storage: storage,
        principalChange: principalChange);
  }

  void listenToAtSignChange(AtSignChangeListener listener) {
    if (!_changeListeners.contains(listener)) {
      _changeListeners.add(listener);
    }
  }

  void _notifyListeners(SwitchAtSignEvent switchAtSignEvent) {
    // Copying the items in _changeListener to a new list to avoid
    // concurrent modification exception when removing the previous
    // atSign listeners
    List<AtSignChangeListener> copyOfChangeListeners =
        List.from(_changeListeners);
    for (var listener in copyOfChangeListeners) {
      listener.listenToAtSignChange(switchAtSignEvent);
    }
  }

  /// Removes the given listener from the list of listeners,
  /// that are notified whenever the @sign is switched
  void removeChangeListeners(AtSignChangeListener atSignChangeListener) {
    _changeListeners.remove((atSignChangeListener));
  }

  /// NOT A PART of API. Added for unit tests
  @visibleForTesting
  int getChangeListenersSize() {
    return _changeListeners.length;
  }

  /// NOT A PART of API. Added for unit tests
  @visibleForTesting
  Iterator<dynamic> getItemsInChangeListeners() {
    return _changeListeners.iterator;
  }

  /// NOT A PART of API. Added for unit tests
  @visibleForTesting
  void removeAllChangeListeners() {
    _changeListeners.clear();
  }

  // NOT a part of API. For functional tests.
  void reset() {
    removeAllChangeListeners();
    _currentAtClient = null;
  }
}

/// Abstraction over the construction of the core services managed by [AtClientManager].
///
/// The default production implementation is [DefaultAtServiceFactory].
/// Override this in tests to inject fakes or mocks without subclassing [AtClientManager].
abstract class AtServiceFactory {
  Future<AtClient> atClient(
    String atSign,
    String? namespace,
    AtClientPreference preference,
    AtClientManager atClientManager, {
    AtChops? atChops,
    AtKeysIo? atKeysIo,
    AtLookUp? atLookUp,
    String? enrollmentId,
    AtClientStorage? storage,
  });

  Future<NotificationService> notificationService(
      AtClient atClient,
      @Deprecated('no longer needed. will be removed in a future release')
      AtClientManager atClientManager,
      {SecondaryAddressFinder? secondaryAddressFinder});

  /// The [notificationService] parameter is ignored — the sync service retrieves
  /// its notification dependency directly from [atClient] after construction.
  Future<SyncService> syncService(AtClient atClient,
      AtClientManager atClientManager, NotificationService notificationService);

  EnrollmentService enrollmentService(AtClient atClient);
}

class DefaultAtServiceFactory implements AtServiceFactory {
  @override
  Future<AtClient> atClient(
    String atSign,
    String? namespace,
    AtClientPreference preference,
    AtClientManager atClientManager, {
    AtChops? atChops,
    AtKeysIo? atKeysIo,
    AtLookUp? atLookUp,
    String? enrollmentId,
    AtClientStorage? storage,
  }) async {
    return await AtClientImpl.create(
      atSign,
      namespace,
      preference,
      atClientManager: atClientManager,
      atChops: atChops,
      atKeysIo: atKeysIo,
      atLookUp: atLookUp,
      enrollmentId: enrollmentId,
      storage: storage,
    );
  }

  @override
  Future<NotificationService> notificationService(
      AtClient atClient, AtClientManager atClientManager,
      {SecondaryAddressFinder? secondaryAddressFinder}) async {
    return await NotificationServiceImpl.create(atClient,
        secondaryAddressFinder: secondaryAddressFinder);
  }

  @override
  Future<SyncService> syncService(
      AtClient atClient,
      @Deprecated('no longer needed. will be removed in a future release')
      AtClientManager atClientManager,
      NotificationService notificationService) async {
    return await SyncServiceImpl.create(atClient);
  }

  @override
  EnrollmentService enrollmentService(AtClient atClient) {
    AtEnrollment atEnrollment = AtEnrollment.create();
    return EnrollmentServiceImpl(atClient, atEnrollment);
  }
}
