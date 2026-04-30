import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
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

  AtClientManager._internal();

  factory AtClientManager.getInstance() {
    return _singleton;
  }

  // ignore: no_leading_underscores_for_local_identifiers
  AtClientManager(this._atSign);

  void setSecondaryAddressFinder(
      {SecondaryAddressFinder? secondaryAddressFinder}) {
    if (secondaryAddressFinder != null) {
      this.secondaryAddressFinder = secondaryAddressFinder;
    }
  }

  /// Switches the active atSign and (re)creates its associated services.
  ///
  /// The outgoing client is stopped via [AtClient.stop] and its instance
  /// remains in cache for resumption. Calling this method again for the same
  /// atSign resumes it with fresh services.
  ///
  /// Use [AtClient.stop] only when permanently finished with an atSign (e.g.,
  /// logout or app shutdown).
  ///
  /// * [serviceFactory] - Overrides service creation (primarily for testing).
  /// * [atChops] - Shared crypto context for the new services.
  Future<AtClientManager> setCurrentAtSign(
      String atSign, String? namespace, AtClientPreference preference,
      {AtServiceFactory? serviceFactory,
      AtChops? atChops,
      AtLookUp? atLookUp,
      String? enrollmentId}) async {
    serviceFactory ??= DefaultAtServiceFactory();

    _logger.info("setCurrentAtSign called with atSign $atSign");
    AtUtils.fixAtSign(atSign);
    secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
        preference.rootDomain, preference.rootPort);

    _logger.info(
        'Switching atSigns ${_currentAtClient?.getCurrentAtSign()} -> $atSign');

    // Stop the outgoing atsign
    _atSign = atSign;
    final previousAtClient = _currentAtClient;
    await previousAtClient?.stop();

    // Spin up the new atClient
    _currentAtClient = await serviceFactory.atClient(
        _atSign, namespace, preference, this,
        atChops: atChops, atLookUp: atLookUp, enrollmentId: enrollmentId);

    var notificationService = await serviceFactory.notificationService(
        _currentAtClient!, this,
        secondaryAddressFinder: secondaryAddressFinder);
    _currentAtClient!.notificationService = notificationService;

    var syncService = await serviceFactory.syncService(
        _currentAtClient!, this, notificationService);
    _currentAtClient!.syncService = syncService;

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

    _logger.info("setCurrentAtSign complete");

    return this;
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
  Future<AtClient> atClient(String atSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager,
      {AtChops? atChops, AtLookUp? atLookUp, String? enrollmentId});

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
  Future<AtClient> atClient(String atSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager,
      {AtChops? atChops, AtLookUp? atLookUp, String? enrollmentId}) async {
    return await AtClientImpl.create(atSign, namespace, preference,
        atClientManager: atClientManager,
        atChops: atChops,
        atLookUp: atLookUp,
        enrollmentId: enrollmentId);
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
