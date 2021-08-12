import 'dart:async';

import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_commons.dart';

abstract class NotificationService {
  // Gives back notifications that matches regex. Regex is optional.
  // notificationCallback is called with regex and the first argument and the Notification bean as the second argument
  // Ex: notificationCallback(regex, Notification)
  void listen(Function notificationCallback, {String? regex});

  Stream<AtNotification> subscribe({String? regex});

  /// Sends notification to [notificationParams.atKey.sharedWith] atSign.
  ///
  /// When await on the method returns [NotificationResult].
  /// when run asynchronously, register to onSuccess and onError callbacks to get [NotificationResult].
  ///
  /// OnSuccess is called when the notification has been delivered to the recipient successfully.
  ///
  /// onError is called when the notification could not delivered
  ///
  ///* Throws [LateInitializationError] when [NotificationParams.atKey] is not initialized
  ///* Throws [AtKeyException] when invalid [NotificationParams.atKey.key] is formed or when
  ///invalid metadata is provided.
  ///* Throws [InvalidAtSignException] on invalid [NotificationParams.atKey.sharedWith] or [NotificationParams.atKey.sharedBy]
  ///* Throws [AtClientException] when keys to encrypt the data are not found.
  ///* Throws [AtClientException] when [notificationParams.notifier] is null when [notificationParams.strategy] is set to latest.
  ///* Throws [AtClientException] when fails to connect to cloud secondary server.
  ///
  /// Usage
  ///
  /// ```dart
  /// var currentAtSign = '@alice'
  /// ```
  ///
  /// 1. To notify update of a key to @bob.
  ///```dart
  ///  var key = AtKey()
  ///    ..key = 'phone'
  ///    ..sharedWith = '@bob';
  ///
  ///  var notification = NotificationServiceImpl(atClient!);
  /// await notification.notify(NotificationParams.forUpdate(key));
  ///```
  ///2. To notify and cache a key to @bob
  ///```dart
  ///  var metaData = Metadata()..ttr = '600000';
  ///  var key = AtKey()
  ///    ..key = 'phone'
  ///    ..sharedWith = '@bob'
  ///    ..metadata = metaData;
  ///
  ///  var notification = NotificationServiceImpl(atClient!);
  /// await notification.notify(NotificationParams.forUpdate(key));
  ///```
  ///3. To notify deletion of a key to @bob.
  ///```dart
  ///  var key = AtKey()
  ///     ..key = 'phone'
  ///     ..sharedWith = '@bob';
  ///
  ///   var notification = NotificationServiceImpl(atClient!);
  ///   await notification.notify(NotificationParams.forDelete(key));
  ///```
  ///4. To notify a text message to @bob
  ///```dart
  ///   var notification = NotificationServiceImpl(atClient!);
  ///   await notification.notify(NotificationParams.forText('Hello','@bob'));
  ///```
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {Function? onSuccess, Function? onError});
}

class NotificationParams {
  late AtKey _atKey;
  String? _value;
  late OperationEnum _operation;
  late MessageTypeEnum _messageType;
  late PriorityEnum _priority;
  late StrategyEnum _strategy;
  final int _latestN = 1;
  final String _notifier = SYSTEM;
  final bool _isDedicated = false;

  AtKey get atKey => _atKey;

  String? get value => _value;

  OperationEnum get operation => _operation;

  MessageTypeEnum get messageType => _messageType;

  PriorityEnum get priority => _priority;

  StrategyEnum get strategy => _strategy;

  String get notifier => _notifier;

  int get latestN => _latestN;

  /// Returns [NotificationParams] to send an update notification.
  static NotificationParams forUpdate(AtKey atKey, {String? value}) {
    return NotificationParams()
      .._atKey = atKey
      .._value = value
      .._operation = OperationEnum.update
      .._messageType = MessageTypeEnum.key
      .._priority = PriorityEnum.low
      .._strategy = StrategyEnum.all;
  }

  /// Returns [NotificationParams] to send an delete notification.
  static NotificationParams forDelete(AtKey atKey) {
    return NotificationParams()
      .._atKey = atKey
      .._operation = OperationEnum.delete
      .._messageType = MessageTypeEnum.key
      .._priority = PriorityEnum.low
      .._strategy = StrategyEnum.all;
  }

  /// Returns [NotificationParams] to send an text message to another atSign.
  static NotificationParams forText(String text, String whomToNotify) {
    var atKey = AtKey()
      ..key = text
      ..sharedWith = whomToNotify;
    return NotificationParams()
      .._atKey = atKey
      .._operation = OperationEnum.update
      .._messageType = MessageTypeEnum.text
      .._priority = PriorityEnum.low
      .._strategy = StrategyEnum.all;
  }
}
