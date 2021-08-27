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
  var _atSign;
  var _previousAtClient;
  late AtClient _currentAtClient;

  AtClient get atClient => _currentAtClient;
  late SyncService syncService;
  late NotificationService notificationService;
  final _changeListeners = <AtSignChangeListener>[];

  static final AtClientManager _singleton = AtClientManager._internal();

  AtClientManager._internal();

  factory AtClientManager.getInstance() {
    return _singleton;
  }

  Future<AtClientManager> setCurrentAtSign(
      String atSign, String? namespace, AtClientPreference preference) async {
    _atSign = atSign;
    _currentAtClient =
        await AtClientImpl.create(_atSign, namespace, preference);
    final switchAtSignEvent =
        SwitchAtSignEvent(_previousAtClient, _currentAtClient);
    notificationService =
        await NotificationServiceImpl.create(_currentAtClient);
    syncService = await SyncServiceImpl.create(_currentAtClient);
    _previousAtClient = _currentAtClient;
    _notifyListeners(switchAtSignEvent);
    return this;
  }

  void listenToAtSignChange(AtSignChangeListener listener) {
    _changeListeners.add(listener);
  }

  void _notifyListeners(SwitchAtSignEvent switchAtSignEvent) {
    _changeListeners.forEach((listener) {
      listener.listenToAtSignChange(switchAtSignEvent);
    });
  }
}
