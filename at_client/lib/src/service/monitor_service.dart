import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';

// #TODO Remove this class..since we have notification service ?
class MonitorService {
  int? _lastNotificationTimestamp;
  late Monitor _monitor;
  late Function _notificationCallback;
  late Function _errorCallback;

  MonitorService(
      Function notificationCallback,
      Function errorCallback,
      String atSign,
      AtClientPreference clientPreference,
      MonitorPreference monitorPreference) {
    _monitor = Monitor(_processNotification, _processError, atSign,
        clientPreference, monitorPreference);
    _notificationCallback = notificationCallback;
    _errorCallback = errorCallback;
  }

  void startMonitor() {
    if (_lastNotificationTimestamp != null) {
      _monitor.start(lastNotificationTime: _lastNotificationTimestamp);
    } else {
      _monitor.start();
    }
  }

  void stopMonitor() {
    _monitor.stop();
  }

  void _processNotification(String notifications) {
    var notificationsList = notifications.split('\n');
    notificationsList.forEach((notification) {
      // split can produce empty strings
      if (notification.isEmpty) return;

      notification = notification.replaceFirst('notification: ', '');
      Map notificationMap = json.decode(notification);
      var currNotificationTimestamp = notificationMap['epochMillis'];
      if (_lastNotificationTimestamp == null ||
          currNotificationTimestamp > _lastNotificationTimestamp) {
        _lastNotificationTimestamp = currNotificationTimestamp;
      }
      _notificationCallback(notification);
    });
  }

  void _processError(Monitor monitor, Exception error) {
    _errorCallback(error);
  }
}