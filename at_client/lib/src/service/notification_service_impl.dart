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
    return instances[atClient.getCurrentAtSign()];
  }

  void _startMonitor() async {
    final lastNotificationId = await _getLastNotificationId();
    final monitor = Monitor(
        _internalNotificationCallback,
        _onMonitorError,
        atClient.getCurrentAtSign()!,
        atClient.getPreferences()!,
        MonitorPreference()..keepAlive = true);
    await monitor.start(lastNotificationTime: lastNotificationId);
  }

  Future<int?> _getLastNotificationId() async {
    final atValue = await atClient.get(AtKey()..key = notificationIdKey);
    if (atValue.value != null) {
      return int.parse(atValue.value);
    }
    return null;
  }

  @override
  void listen(Function notificationCallback, {String? regex}) {
    regex ??= EMPTY_REGEX;
    listeners[regex] = notificationCallback;
  }

  void _internalNotificationCallback(String notificationJSON) async {
    final atNotification =
        AtNotification.fromJson(jsonDecode(notificationJSON));
    await atClient.put(
        AtKey()..key = notificationIdKey, atNotification.notificationId);
    listeners.forEach((regex, subscriptionCallback) {
      if(regex != EMPTY_REGEX) {
        final isMatches = regex
            .allMatches(atNotification.key)
            .isNotEmpty;
        if (isMatches) {
          subscriptionCallback(atNotification);
        }
      } else {
        subscriptionCallback(atNotification);
      }
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
  late int notificationId;
  late String key;
  dynamic? value;

  static AtNotification fromJson(Map json) {
    return AtNotification()
      ..notificationId = json['notificationId']
      ..key = json['key'];
  }

  Map toJson() {
    final jsonMap = {};
    jsonMap['notificationId'] = notificationId;
    jsonMap['key'] = key;
    return jsonMap;
  }
}
