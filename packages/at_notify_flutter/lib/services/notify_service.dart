// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_notify_flutter/models/notify_model.dart';
import 'package:at_notify_flutter/utils/notify_utils.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A service to handle save and retrieve operation on notify
class NotifyService {
  NotifyService._();

  static final NotifyService _instance = NotifyService._();

  factory NotifyService() => _instance;

  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  late InitializationSettings initializationSettings;

  final String storageKey = 'at_notify';

  late AtClientManager atClientManager;
  late AtClient atClient;

  String? rootDomain;
  int? rootPort;
  String? currentAtSign;

  /// List to store notification objects
  List<Notify> notifies = [];

  /// Stream to put the notification object list
  StreamController<List<Notify>> notifyStreamController = StreamController<List<Notify>>.broadcast();

  Sink get notifySink => notifyStreamController.sink;

  Stream<List<Notify>> get notifyStream => notifyStreamController.stream;

  void disposeControllers() {
    notifyStreamController.close();
  }

  /// Initialise function to set the client preference, atsign and root domain
  void initNotifyService(AtClientPreference atClientPreference, String currentAtSignFromApp, String rootDomainFromApp,
      int rootPortFromApp) async {
    currentAtSign = currentAtSignFromApp;
    rootDomain = rootDomainFromApp;
    rootPort = rootPortFromApp;
    atClientManager = AtClientManager.getInstance();
    AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSignFromApp, atClientPreference.namespace, atClientPreference);
    atClient = AtClientManager.getInstance().atClient;
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    atClientManager.atClient.notificationService
        .subscribe(regex: '.${atClientPreference.namespace}', shouldDecrypt: true)
        .listen((AtNotification notification) {
      _notificationCallback(notification);
    });

    if (Platform.isIOS) {
      _requestIOSPermission();
    }
    await initializePlatformSpecifics();
  }

  /// Initialized Notification Settings
  initializePlatformSpecifics() async {
    var initializationSettingsAndroid = const AndroidInitializationSettings('@mipmap/ic_launcher');
    var initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        var receivedNotification = ReceivedNotification(
          id: id,
          title: title!,
          body: body!,
          payload: payload!,
        );
        print('receivedNotification: ${receivedNotification.toString()}');
        //     didReceivedLocalNotificationSubject.add(receivedNotification);
      },
    );
    initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid, iOS: initializationSettingsIOS);

    await _notificationsPlugin.initialize(
      initializationSettings,
    );
  }

  /// Request Alert, Badge, Sound Permission for IOS
  _requestIOSPermission() {
    _notificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()!
        .requestPermissions(
          alert: false,
          badge: true,
          sound: true,
        );
  }

  /// Listen Notification
  void _notificationCallback(AtNotification notification) async {
    print('_notificationCallback called in at_notify_flutter');
    AtNotification atNotification = notification;
    var notificationKey = atNotification.key;
    var fromAtsign = atNotification.from;
    var toAtsign = atNotification.to;

    // remove from and to atsigns from the notification key
    if (notificationKey.contains(':')) {
      notificationKey = notificationKey.split(':')[1];
    }
    notificationKey = notificationKey.replaceFirst(fromAtsign, '').trim();
    print('notificationKey = $notificationKey');

    if (atNotification.id == '-1') {
      return;
    }

    if ((notificationKey.startsWith(storageKey) && toAtsign == currentAtSign)) {
      var message = atNotification.value ?? '';
      print('notify message => $message $fromAtsign');
      if (message.isNotEmpty && message != 'null') {
        var decryptedMessage = notification.value!;
        print('notify decryptedMessage => $decryptedMessage $fromAtsign');
        await showNotification(decryptedMessage, fromAtsign);
      }
    }
  }

  /// Get Notify List From AtClient
  Future<void> getNotifies({String? atsign, int days = 1}) async {
    try {
      var currentDate = DateTime.now().subtract(Duration(days: days));
      var _fromDate = '${currentDate.year}';

      if (currentDate.month < 10) {
        _fromDate = '$_fromDate-0${currentDate.month}';
      } else {
        _fromDate = '$_fromDate-${currentDate.month}';
      }

      if (currentDate.day < 10) {
        _fromDate = '$_fromDate-0${currentDate.day}';
      } else {
        _fromDate = '$_fromDate-${currentDate.day}';
      }

      notifies = [];
      notifySink.add(notifies);

      var notificationsKey = await atClient.getAtKeys(regex: storageKey);

      if (notificationsKey.isEmpty) {
        return;
      }

      for (var atKey in notificationsKey) {
        var _notificationData = await atClient.get(atKey);
        var _newNotifyObj = Notify.fromJson(_notificationData.value);

        notifies.insert(0, _newNotifyObj);
        notifySink.add(notifies);
      }
    } catch (error) {
      print('Error in getNotifies -> $error');
    }
  }

  /// Call Notify in NotificationService, send notify to others
  Future<bool> sendNotify(String sendToAtSign, Notify notify, NotifyEnum notifyType, {int noOfDays = 30}) async {
    if (!sendToAtSign.contains('@')) {
      sendToAtSign = '@$sendToAtSign';
    }
    var metadata = Metadata();
    metadata.ttr = -1;
    metadata.ttl = 30 * 24 * 60 * 60000; // in milliseconds
    var key = AtKey()
      ..key = storageKey
      ..sharedBy = currentAtSign
      ..sharedWith = sendToAtSign
      ..metadata = metadata;
    var notificationResponse = await atClientManager.atClient.notificationService.notify(
      NotificationParams.forUpdate(key, value: notify.toJson()),
    );

    if (notificationResponse.notificationStatusEnum == NotificationStatusEnum.delivered) {
      print(notificationResponse.toString());
    } else {
      print(notificationResponse.atClientException.toString());
      return false;
    }
    return true;
  }

  /// Show Local Notification in Device
  Future<void> showNotification(String decryptedMessage, String atSign) async {
    Notify notify = Notify.fromJson((decryptedMessage));
    print('showNotification => ${notify.message} ${notify.atSign}');

    var androidChannelSpecifics = const AndroidNotificationDetails(
      'notify_id',
      'notify',
      channelDescription: "notify_description",
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      timeoutAfter: 50000,
      styleInformation: DefaultStyleInformation(true, true),
    );
    var iosChannelSpecifics = const DarwinNotificationDetails();

    var platformChannelSpecifics = NotificationDetails(android: androidChannelSpecifics, iOS: iosChannelSpecifics);
    await _notificationsPlugin.show(
      0,
      atSign,
      '${notify.message}',
      platformChannelSpecifics,
      payload: notify.message,
    );
  }

  /// Cancel All notification
  void cancelNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}

/// Model for received notification
class ReceivedNotification {
  final int id;
  final String title;
  final String body;
  final String payload;

  ReceivedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });
}
