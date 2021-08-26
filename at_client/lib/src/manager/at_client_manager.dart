import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';

class AtClientManager {
  var _atSign;
  late var atClient;
  late var syncService;
  late var notificationService;
  final _changeListeners = <AtSignChangeListener>[];

  static final AtClientManager _singleton = AtClientManager._internal();

  AtClientManager._internal();

  factory AtClientManager.getInstance() {
    return _singleton;
  }

  void setCurrentAtSign(
      String atSign, String namespace, AtClientPreference preference) {
    _atSign = _atSign;
    final previousAtClient = atClient;
    atClient = AtClientImpl.create(_atSign, namespace, preference);
    final switchAtSignEvent = SwitchAtSignEvent(previousAtClient, atClient);
    syncService = SyncServiceImpl.create(atClient);
    notificationService = NotificationServiceImpl.create(atClient);
    _notifyListeners(switchAtSignEvent);
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
