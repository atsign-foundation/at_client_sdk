import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_client/src/service/sync_service_impl.dart';

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
  late String _atSign;
  AtClient? _previousAtClient;
  late AtClient _currentAtClient;

  AtClient get atClient => _currentAtClient;
  late SyncService syncService;
  late NotificationService notificationService;
  final _changeListeners = <AtSignChangeListener>[];

  static final AtClientManager _singleton = AtClientManager._internal();

  AtClientManager._internal();

  @deprecated
  factory AtClientManager.getInstance() {
    return _singleton;
  }

  AtClientManager(_atSign);

  Future<AtClientManager> setCurrentAtSign(
      String atSign, String? namespace, AtClientPreference preference) async {
    if (_previousAtClient != null &&
        _previousAtClient?.getCurrentAtSign() == atSign) {
      return this;
    }
    _currentAtClient = await AtClientImpl.create(_atSign, namespace, preference,
        atClientManager: this);
    final switchAtSignEvent =
        SwitchAtSignEvent(_previousAtClient, _currentAtClient);
    notificationService =
        await NotificationServiceImpl.create(_currentAtClient);
    syncService =
        await SyncServiceImpl.create(_currentAtClient, atClientManager: this);
    _previousAtClient = _currentAtClient;
    _notifyListeners(switchAtSignEvent);
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
