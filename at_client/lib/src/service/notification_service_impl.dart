import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';

class NotificationServiceImpl implements NotificationService {
  Map<String, NotificationService> instances = {};
  Map<String, Function> listeners = {};
  final EMPTY_REGEX = '';
  static const notificationIdKey = '_latestNotificationId';

  late AtClient atClient;

  NotificationServiceImpl(this.atClient);

  NotificationService? getInstance() {
    _startMonitor();
    instances[atClient.getCurrentAtSign()!] = this;
    return instances[atClient.getCurrentAtSign()];
  }

  void _startMonitor() async {
    final lastNotificationTime = await _getLastNotificationTime();
    final monitor = Monitor(
        _internalNotificationCallback,
        _onMonitorError,
        atClient.getCurrentAtSign()!,
        atClient.getPreferences()!,
        MonitorPreference()..keepAlive = true);
    print(
        'starting monitor with last notification time: $lastNotificationTime');
    await monitor.start(lastNotificationTime: lastNotificationTime);
  }

  Future<int?> _getLastNotificationTime() async {
    final atValue = await atClient.get(AtKey()..key = notificationIdKey);
    if (atValue.value != null) {
      print('json from hive: ${atValue.value}');
      return jsonDecode(atValue.value)['epochMillis'];
    }
    return null;
  }

  @override
  void listen(Function notificationCallback, {String? regex}) {
    regex ??= EMPTY_REGEX;
    listeners[regex] = notificationCallback;
    print('added regex to listener $regex');
  }

  void _internalNotificationCallback(String notificationJSON) async {
    // #TODO move some of this logic to notification parser
    var notifications = notificationJSON.split('notification: ');
    notifications.forEach((notification) async {
      if (notification.isEmpty) {
        print('empty string in notification');
        return;
      }
      notification = notification.replaceFirst('notification:', '');
      notification = notification.trim();
      print(notification);
      final atNotification = AtNotification.fromJson(jsonDecode(notification));
      print('processing ${atNotification.notificationId}');
      await atClient.put(AtKey()..key = notificationIdKey, notification);
      listeners.forEach((regex, subscriptionCallback) {
        if (regex != EMPTY_REGEX) {
          final isMatches = regex.allMatches(atNotification.key).isNotEmpty;
          if (isMatches) {
            subscriptionCallback(atNotification);
          }
        } else {
          subscriptionCallback(atNotification);
        }
      });
    });
  }

  void _onMonitorError() {
    //#TODO implement
  }

  @override
  void notify(NotificationParams notificationParams, onSuccessCallback,
      onErrorCallback) {
    // TODO: implement notify
  }
}

class AtNotification {
  late String notificationId;
  late String key;
  late int epochMillis;

  static AtNotification fromJson(Map json) {
    return AtNotification()
      ..notificationId = json['id']
      ..key = json['key']
      ..epochMillis = json['epochMillis'];
  }

  Map toJson() {
    final jsonMap = {};
    jsonMap['id'] = notificationId;
    jsonMap['key'] = key;
    jsonMap['epochMillis'] = epochMillis;
    return jsonMap;
  }

  @override
  String toString() {
    return 'AtNotification{notificationId: $notificationId, key: $key, epochMillis: $epochMillis}';
  }
}
