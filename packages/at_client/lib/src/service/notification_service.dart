import 'dart:async';

import 'package:at_client/src/response/at_notification.dart';
import 'package:at_commons/at_commons.dart';
import 'package:uuid/uuid.dart';

abstract class NotificationService {
  /// Gives back stream of notifications from the server to the subscribing client.
  ///
  /// Optionally pass a regex to filter notification keys matching the regex.
  ///
  /// Optionally set shouldDecrypt to true to return the original value in the [AtNotification]
  /// Defaulted to false to preserve the backward compatibility.
  Stream<AtNotification> subscribe({String? regex, bool shouldDecrypt});

  /// Sends notification to [notificationParams.atKey.sharedWith] atSign.
  ///
  /// Returns [NotificationResult] when calling the method synchronously using `await`. Be aware that it could take
  /// many minutes before we get to a final delivery status when we run synchronously, so we advise against that.
  /// However there is something in between 'fire and forget' and 'wait a long time' available - if you call the
  /// method synchronously using `await` but you also set [waitForFinalDeliveryStatus] to false, then the future
  /// will complete once the notification has been successfully sent to our cloud secondary, which is thereafter
  /// responsible for forwarding to the recipient; the polling for delivery status will continue asynchronously
  /// and eventually your provided [onSuccess] or [onError] function will be called.
  ///
  /// If you set the optional [checkForFinalDeliveryStatus] parameter to false, then you can prevent the polling for
  /// final delivery status to be done at all by this method, and instead if you need to, you can do the periodic
  /// checking for final delivery status elsewhere in your code.
  ///
  /// When run asynchronously, register to onSentToSecondary, onSuccess and onError callbacks to get [NotificationResult].
  ///
  /// onSentToSecondary is called when the notification has been sent from our client to our cloud secondary
  ///
  /// onSuccess is called when the notification has been delivered to the recipient's secondary successfully.
  ///
  /// onError is called when the notification could not delivered. Note that this could be a very long time
  ///
  /// Following exceptions are encapsulated in [NotificationResult.atClientException]
  ///* [AtKeyException] when invalid [NotificationParams.atKey.key] is formed or when
  ///invalid metadata is provided.
  ///* [InvalidAtSignException] on invalid [NotificationParams.atKey.sharedWith] or [NotificationParams.atKey.sharedBy]
  ///* [AtClientException] when keys to encrypt the data are not found.
  ///* [AtClientException] when [notificationParams.notifier] is null when [notificationParams.strategy] is set to latest.
  ///* [AtClientException] when fails to connect to cloud secondary server.
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
  ///  var notificationService = AtClientManager.getInstance().notificationService;
  ///  await notificationService.notify(NotificationParams.forUpdate(key));
  ///```
  ///2. To notify and cache a key to @bob
  ///```dart
  ///  var metaData = Metadata()..ttr = '600000';
  ///  var key = AtKey()
  ///    ..key = 'phone'
  ///    ..sharedWith = '@bob'
  ///    ..metadata = metaData;
  ///
  ///  var value = '+1 998 999 4940'
  ///
  ///  var notificationService = AtClientManager.getInstance().notificationService;
  ///  await notificationService.notify(NotificationParams.forUpdate(key, value: value));
  ///```
  ///3. To notify deletion of a key to @bob.
  ///```dart
  ///  var key = AtKey()
  ///     ..key = 'phone'
  ///     ..sharedWith = '@bob';
  ///
  ///   var notificationService = AtClientManager.getInstance().notificationService;
  ///   await notificationService.notify(NotificationParams.forDelete(key));
  ///```
  ///4. To notify a text message to @bob
  ///   forText notifications are case sensitive
  ///   await notificationService.notify(NotificationParams.forText(<Text to Notify>,<Whom to Notify>));
  ///
  ///```dart
  ///   var notificationService = AtClientManager.getInstance().notificationService;
  ///   await notificationService.notify(NotificationParams.forText('Hello','@bob'));
  ///```
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {bool waitForFinalDeliveryStatus =
          true, // this was the behaviour before introducing this parameter
      bool checkForFinalDeliveryStatus =
          true, // this was the behaviour before introducing this parameter
      Function(NotificationResult)? onSuccess,
      Function(NotificationResult)? onError,
      Function(NotificationResult)? onSentToSecondary});

  /// Stops all subscriptions on the current instance
  void stopAllSubscriptions();

  /// Returns the status of the given notificationId
  ///
  /// Usage:
  ///
  /// To get the status of a notification
  ///```dart
  /// var notificationService = AtClientManager.getInstance().notificationService;
  /// var notificationResult = await notificationService.status('abc-123');
  ///```
  ///
  /// * Returns [NotificationResult] for the given notification-id.
  ///
  /// * When notification is delivered successfully, [NotificationResult.notificationStatusEnum] is set to delivered
  ///
  /// * When notification is fail to deliver, [NotificationResult.notificationStatusEnum] is set to undelivered
  ///
  /// * The exception are captured in [NotificationResult.atClientException]
  Future<NotificationResult> getStatus(String notificationId);

  /// Returns the [AtNotification] of the given notificationId
  ///
  /// Usage:
  ///
  ///  To fetch a notification with id: abc-123
  /// ```dart
  /// var notificationService = AtClientManager.getInstance().notificationService;
  /// var atNotification = await notificationService.fetch('abc-123');
  /// ```
  /// Returns [NotificationStatus.delivered] when notification exist in the key-store
  /// ```
  ///  AtNotification{id: abc-123, key: @bob:phone.wavi@alice,
  ///  from: @alice, to: @bob, epochMillis: 1666268427030, value: "+1 887 887 7876",
  ///  operation: OperationType.update, status: NotificationStatus.delivered}
  /// ```
  ///
  /// Returns [NotificationStatus.expired] when
  /// * Notification id does not exist
  /// * Notification is expired / delete
  /// ```
  ///  AtNotification{id: abc-123, status: NotificationStatus.expired}
  /// ```
  /// Throws [AtClientException] when server is not reachable or server timeout's to respond
  Future<AtNotification> fetch(String notificationId);
}

/// [NotificationParams] represents a notification input params.
class NotificationParams {
  late String _id;
  late AtKey _atKey;
  String? _value;
  late OperationEnum _operation;
  late MessageTypeEnum _messageType;
  PriorityEnum _priority = PriorityEnum.low;
  StrategyEnum _strategy = StrategyEnum.all;
  int _latestN = 1;
  String _notifier = AtConstants.system;
  Duration _notificationExpiry = Duration(hours: 24);

  String get id => _id;

  AtKey get atKey => _atKey;

  String? get value => _value;

  OperationEnum get operation => _operation;

  MessageTypeEnum get messageType => _messageType;

  PriorityEnum get priority => _priority;

  StrategyEnum get strategy => _strategy;

  String get notifier => _notifier;

  int get latestN => _latestN;

  Duration get notificationExpiry => _notificationExpiry;

  /// Returns [NotificationParams] to send an update notification.
  ///
  /// Optionally accepts the following
  ///
  /// * priority: Represents the priority of the notification. The notification marked [PriorityEnum.high] takes precedence over other notifications.
  ///
  /// * strategy: When notifications marked with [StrategyEnum.all], all the notifications are sent. For [StrategyEnum.latest], only the [latestN] of a notifier are sent
  ///
  /// * latestN: Represents the count of notifications to store that belong to a particular [notifier].
  ///
  /// * notifier: Groups the notifications that has the same notifier.
  ///
  /// * notificationExpiry: Refers to the amount of time the notification is
  /// available in the KeyStore. Beyond which the notification is removed from the KeyStore.
  static NotificationParams forUpdate(AtKey atKey,
      {String? value,
      PriorityEnum priority = PriorityEnum.low,
      StrategyEnum strategy = StrategyEnum.all,
      int latestN = 1,
      String notifier = AtConstants.system,
      Duration? notificationExpiry}) {
    return NotificationParams()
      .._id = Uuid().v4()
      .._atKey = atKey
      .._value = value
      .._operation = OperationEnum.update
      .._messageType = MessageTypeEnum.key
      .._priority = priority
      .._strategy = strategy
      .._latestN = latestN
      .._notifier = notifier
      .._notificationExpiry = notificationExpiry ?? Duration(hours: 24);
  }

  /// Returns [NotificationParams] to send a delete notification.
  static NotificationParams forDelete(AtKey atKey) {
    return NotificationParams()
      .._id = Uuid().v4()
      .._atKey = atKey
      .._operation = OperationEnum.delete
      .._messageType = MessageTypeEnum.key;
  }

  /// Returns [NotificationParams] to send a text message to another atSign.
  /// forText notifications are case-sensitive
  /// platform level lower case enforcement will not apply to forText notifications
  static NotificationParams forText(String text, String whomToNotify,
      {bool shouldEncrypt = false}) {
    var atKey = AtKey()
      ..key = text
      ..sharedWith = whomToNotify
      ..metadata = (Metadata()..isEncrypted = shouldEncrypt);
    return NotificationParams()
      .._id = Uuid().v4()
      .._atKey = atKey
      .._operation = OperationEnum.update
      .._messageType = MessageTypeEnum.text;
  }
}

/// [NotificationResult] encapsulates the notification response
class NotificationResult {
  late String notificationID;
  AtKey? atKey;
  NotificationStatusEnum notificationStatusEnum =
      NotificationStatusEnum.undelivered;

  AtClientException? atClientException;

  @override
  String toString() {
    return 'id: $notificationID status: $notificationStatusEnum';
  }
}

/// The configurations for the Notification listeners
class NotificationConfig {
  /// To filter notification keys matching the regex
  String regex = '';

  /// To enable/disable decrypting of the value in the [AtNotification]
  /// Defaulted to false to preserve backward compatibility.
  bool shouldDecrypt = false;
}

enum NotificationStatusEnum { delivered, undelivered }
