import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
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

  AtClient get atClient => _currentAtClient!;

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
  AtClientManager(_atSign);

  void setSecondaryAddressFinder(
      {SecondaryAddressFinder? secondaryAddressFinder}) {
    if (secondaryAddressFinder != null) {
      this.secondaryAddressFinder = secondaryAddressFinder;
    }
  }

  /// * Can provide an [AtServiceFactory] to control what types of AtClients, NotificationServices and SyncServices get created
  /// by this method.
  /// * Can provide an [AtChops] instance if available; setCurrentAtSign will ensure that it is injected into objects that
  /// can use it
  Future<AtClientManager> setCurrentAtSign(
      String atSign, String? namespace, AtClientPreference preference,
      {AtServiceFactory? serviceFactory,
      AtChops? atChops,
      String? enrollmentId}) async {
    serviceFactory ??= DefaultAtServiceFactory();

    _logger.info("setCurrentAtSign called with atSign $atSign");
    AtUtils.fixAtSign(atSign);
    secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
        preference.rootDomain, preference.rootPort);
    if (_currentAtClient != null &&
        _currentAtClient?.getCurrentAtSign() == atSign) {
      _logger.info(
          'previous currentAtSign ${_currentAtClient?.getCurrentAtSign()} is same as new atSign $atSign - doing nothing, returning');
      return this;
    }

    _logger.info(
        'Switching atSigns from ${_currentAtClient?.getCurrentAtSign()} to $atSign');
    _atSign = atSign;
    var previousAtClient = _currentAtClient;
    _currentAtClient = await serviceFactory.atClient(
        _atSign, namespace, preference, this,
        atChops: atChops, enrollmentId: enrollmentId);
    final switchAtSignEvent =
        SwitchAtSignEvent(previousAtClient, _currentAtClient!);
    _notifyListeners(switchAtSignEvent);

    var notificationService =
        await serviceFactory.notificationService(_currentAtClient!, this);
    _currentAtClient!.notificationService = notificationService;

    var syncService = await serviceFactory.syncService(
        _currentAtClient!, this, notificationService);
    _currentAtClient!.syncService = syncService;

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
  removeAllChangeListeners() {
    _changeListeners.clear();
  }
}

abstract class AtServiceFactory {
  Future<AtClient> atClient(String atSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager,
      {AtChops? atChops, String? enrollmentId});

  Future<NotificationService> notificationService(
      AtClient atClient, AtClientManager atClientManager);

  Future<SyncService> syncService(AtClient atClient,
      AtClientManager atClientManager, NotificationService notificationService);
}

class DefaultAtServiceFactory implements AtServiceFactory {
  @override
  Future<AtClient> atClient(String atSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager,
      {AtChops? atChops, String? enrollmentId}) async {
    return await AtClientImpl.create(atSign, namespace, preference,
        atClientManager: atClientManager,
        atChops: atChops,
        enrollmentId: enrollmentId);
  }

  @override
  Future<NotificationService> notificationService(
      AtClient atClient, AtClientManager atClientManager) async {
    return await NotificationServiceImpl.create(atClient,
        atClientManager: atClientManager);
  }

  @override
  Future<SyncService> syncService(
      AtClient atClient,
      AtClientManager atClientManager,
      NotificationService notificationService) async {
    return await SyncServiceImpl.create(atClient,
        atClientManager: atClientManager,
        notificationService: notificationService);
  }
}
