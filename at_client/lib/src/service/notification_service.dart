import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_commons/at_commons.dart';

abstract class NotificationService {
  // Gives back notifications that matches regex. Regex is optional.
  // notificationCallback is called with regex and the first argument and the Notification bean as the second argument
  // Ex: notificationCallback(regex, Notification)
  void listen(Function notificationCallback, {String? regex});

  // Sends notification.
  // onSuccessCallback is called when the notification gas been delivered to the recipient successfully.
  // onErrorCallback is called when the notification could not delivered
  Future<NotificationResult> notify(NotificationParams notificationParams,
      onSuccessCallback, onErrorCallback);
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

  static NotificationParams forUpdate(AtKey atKey, {String? value}) {
    return NotificationParams()
      .._atKey = atKey
      .._value = value
      .._operation = OperationEnum.update
      .._messageType = MessageTypeEnum.key
      .._priority = PriorityEnum.low
      .._strategy = StrategyEnum.all;
  }

  static NotificationParams forDelete(AtKey atKey) {
    return NotificationParams()
      .._atKey = atKey
      .._operation = OperationEnum.delete
      .._messageType = MessageTypeEnum.key
      .._priority = PriorityEnum.low
      .._strategy = StrategyEnum.all;
  }

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
