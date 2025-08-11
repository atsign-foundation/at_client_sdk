//A service to handle notifications when an atsign follows another atsign
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/at_client.dart' as at_client;

//Service to operate notifications
class NotificationService {
  static final notificationService = NotificationService._internal();
  NotificationService._internal() {
    init();
  }

  final _logger = AtSignLogger('Notification Service');
  factory NotificationService() => notificationService;
  late InitializationSettings initializationSettings;
  late FlutterLocalNotificationsPlugin _notificationsPlugin;

  init() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    if (Platform.isIOS) {
      _requestIOSPermissions();
    }
    initializePlatformSpecifics();
    _logger.info('initialiazed notification service');
  }

  ///Gets called when user clicks on notification
  setOnNotificationClick(Function onNotificationClick) async {
    await _notificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse: (payload) async {
      await onNotificationClick(payload);
    });
  }

  ///Initialize the notification settings for iOS and Android
  initializePlatformSpecifics() {
    var initializationSettingsAndroid =
        AndroidInitializationSettings('notification_icon');
    var initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        _logger.info(
            'received notification ::id $id, title $title, body $body, payload $payload');
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

  // method to display notification
  showNotification(at_client.AtNotification atNotification) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'CHANNEL_ID',
      'CHANNEL_NAME',
      //'CHANNEL_DESCRIPTION',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      styleInformation: BigTextStyleInformation(''),
    );
    var iosChannelSpecifics = DarwinNotificationDetails();

    var platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics, iOS: iosChannelSpecifics);
    await _notificationsPlugin.show(
        0,
        '${atNotification.from} is following your ${atNotification.to} @sign',
        'Open the app to follow them back',
        platformChannelSpecifics,
        payload: jsonEncode(atNotification.toJson()));
  }

  // method to cancel the notification
  cancelNotification() async {
    await _notificationsPlugin.cancelAll();
  }
}
