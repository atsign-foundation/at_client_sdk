import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';

class MonitorService {
  int _lastNotificationTimestamp;
  Monitor _monitor;
  Function _notificationCallback;
  Function _errorCallback;

  MonitorService(
      Function notificationCallback,
      Function errorCallback,
      String atSign,
      AtClientPreference clientPreference,
      {String regex}) {
    _monitor = Monitor(_processNotification, _processError, atSign, clientPreference, regex: regex);
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

  void _processNotification(String notification) {
    notification = notification.replaceFirst('notification: ', '');
    print(notification + "\n");

    Map notificationMap = json.decode(notification);
    var currNotificationTimestamp = notificationMap['epochMillis'];
    if (_lastNotificationTimestamp == null || currNotificationTimestamp > _lastNotificationTimestamp) {
      _lastNotificationTimestamp = currNotificationTimestamp;
    }
    _notificationCallback(notification);
  }

  void _processError(Monitor monitor, Exception error) {
    _errorCallback(error);
  }
}