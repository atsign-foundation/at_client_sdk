import 'dart:convert';

import 'package:at_follows_flutter_example/services/at_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';

class NotificationService {
  static final notificationService = NotificationService._internal();
  NotificationService._internal() {
    init();
  }

  factory NotificationService() => notificationService;
  late InitializationSettings initializationSettings;
  late FlutterLocalNotificationsPlugin _notificationsPlugin;

  init() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    if (Platform.isIOS) {
      _requestIOSPermissions();
    }
    initializePlatformSpecifics();
    print('initialiazed notification service');
  }

  setOnNotificationClick(Function onNotificationClick) async {
    await _notificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse: (payload) async {
      await onNotificationClick(payload);
    });
  }

  initializePlatformSpecifics() {
    var initializationSettingsAndroid =
        AndroidInitializationSettings('notification_icon');
    var initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        print('id $id, title $title, body $body, payload $payload');
      },
    );

    initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
  }

  _requestIOSPermissions() {
    _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: false,
          badge: true,
          sound: true,
        );
  }

  showNotification(AtNotification atNotification) async {
    print('inside show notification...');
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails('your channel id', 'your channel name',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: false);
    var iosChannelSpecifics = DarwinNotificationDetails();

    var platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics, iOS: iosChannelSpecifics);
    await _notificationsPlugin.show(
        0,
        '${atNotification.from} is following your ${atNotification.to}',
        'Open the app to follow them back',
        platformChannelSpecifics,
        payload: jsonEncode(atNotification.toJson()));
  }

  cancelNotification() async {
    await _notificationsPlugin.cancelAll();
  }
}
