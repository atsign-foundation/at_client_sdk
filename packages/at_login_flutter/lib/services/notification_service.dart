import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/at_client.dart' as at_client;

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

  setOnNotificationClick(Function onNotificationClick) async {
    await _notificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse payload) {
          onNotificationClick(payload);
        });
  }

  initializePlatformSpecifics() {
    var initializationSettingsAndroid =
        AndroidInitializationSettings('notification_icon');
    var initializationSettingsIOS = 
    DarwinInitializationSettings(
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

  showNotification(at_client.AtNotification atNotification) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'CHANNEL_ID',
      'CHANNEL_NAME',
      channelDescription: 'CHANNEL_DESCRIPTION',
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

  cancelNotification() async {
    await _notificationsPlugin.cancelAll();
  }
}
