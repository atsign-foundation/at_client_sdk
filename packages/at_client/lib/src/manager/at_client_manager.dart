import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_utils.dart';

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
  String? _atSign;
  AtClient? _previousAtClient;
  late AtClient _currentAtClient;

  AtClient get atClient => _currentAtClient;
  late SyncService syncService;
  late NotificationService notificationService;
  SecondaryAddressFinder? secondaryAddressFinder;
  final _changeListeners = <AtSignChangeListener>[];

  static final AtClientManager _singleton = AtClientManager._internal();

  static final _logger = AtSignLogger('AtClientManager');


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

  Future<AtClientManager> setCurrentAtSign(
      String atSign, String? namespace, AtClientPreference preference) async {
    _logger.info("setCurrentAtSign called with atSign $atSign");
    AtUtils.fixAtSign(atSign);
    secondaryAddressFinder ??= CacheableSecondaryAddressFinder(
        preference.rootDomain, preference.rootPort);
    if (_previousAtClient != null &&
        _previousAtClient?.getCurrentAtSign() == atSign) {
      _logger.info("setCurrentAtSign complete: atSign is same as current atSign");
      return this;
    }

    String? previousAtSign = _atSign;

    _atSign = atSign;

    _logger.info("setCurrentAtSign calling AtClientImpl.create for $_atSign");
    _currentAtClient = await AtClientImpl.create(_atSign!, namespace, preference,
        atClientManager: this);
    final switchAtSignEvent =
        SwitchAtSignEvent(_previousAtClient, _currentAtClient);

    _logger.info("setCurrentAtSign calling NotificationServiceImpl.create for $_atSign");
    notificationService = await NotificationServiceImpl.create(_currentAtClient,
        atClientManager: this);
    _logger.info("setCurrentAtSign setting notificationService on the AtClient");
    _currentAtClient.notificationService = notificationService;

    _logger.info("setCurrentAtSign calling SyncServiceImpl.create for $_atSign");
    syncService = await SyncServiceImpl.create(_currentAtClient,
        atClientManager: this, notificationService: notificationService);
    _logger.info("setCurrentAtSign setting syncService on the AtClient");
    _currentAtClient.syncService = syncService;

    _previousAtClient = _currentAtClient;


    _logger.info("setCurrentAtSign notifying listeners we are switching atSigns from $previousAtSign to $_atSign");
    _notifyListeners(switchAtSignEvent);

    _logger.info("setCurrentAtSign complete");
    return this;
  }

  void listenToAtSignChange(AtSignChangeListener listener) {
    _changeListeners.add(listener);
  }

  void _notifyListeners(SwitchAtSignEvent switchAtSignEvent) {
    for (var listener in _changeListeners) {
      listener.listenToAtSignChange(switchAtSignEvent);
    }
  }
}
