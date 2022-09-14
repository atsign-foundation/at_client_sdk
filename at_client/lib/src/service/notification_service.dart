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
  ///  var value = '+1 998 999 4940'
  ///
  ///  var notification = NotificationServiceImpl(atClient!);
  /// await notification.notify(NotificationParams.forUpdate(key, value: value));
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
  ///   await notification.notify(NotificationParams.forText(<Text to Notify>,<Whom to Notify>));
  ///
  ///```dart
  ///   var notification = NotificationServiceImpl(atClient!);
  ///   await notification.notify(NotificationParams.forText('Hello','@bob'));
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
  Future<NotificationResult> getStatus(String notificationId);
}

/// [NotificationParams] represents a notification input params.
class NotificationParams {
  late String _id;
  late AtKey _atKey;
  String? _value;
  late OperationEnum _operation;
  late MessageTypeEnum _messageType;

  /// Represents the priority of the Notification.
  /// By default, all the notifications are set to low priority
  PriorityEnum priority = PriorityEnum.low;

  /// Represents the strategy of the Notification.
  /// By default, all the notifications are set to strategy - 'all' .
  StrategyEnum strategy = StrategyEnum.all;

  /// Represents the most recent 'N' notifications to be delivered. Defaults to 1.
  int latestN = 1;

  /// Groups the notifications
  String notifier = SYSTEM;

  /// Represents the time for the notification to expire. Defaults to 15 minute
  Duration notificationExpiry = Duration(minutes: 15);

  String get id => _id;

  AtKey get atKey => _atKey;

  String? get value => _value;

  OperationEnum get operation => _operation;

  MessageTypeEnum get messageType => _messageType;

  /// Returns [NotificationParams] to send an update notification.
  static NotificationParams forUpdate(AtKey atKey, {String? value}) {
    return NotificationParams()
      .._id = Uuid().v4()
      .._atKey = atKey
      .._value = value
      .._operation = OperationEnum.update
      .._messageType = MessageTypeEnum.key;
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
