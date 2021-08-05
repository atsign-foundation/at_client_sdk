import 'package:at_commons/at_commons.dart';

abstract class NotificationService {
  // Gives back notifications that matches regex. Regex is optional.
  // notificationCallback is called with regex and the first argument and the Notification bean as the second argument
  // Ex: notificationCallback(regex, Notification)
  void listen(Function notificationCallback, {String? regex});

  // Sends notification.
  // onSuccessCallback is called when the notification gas been delivered to the recipient successfully.
  // onErrorCallback is called when the notification could not delivered
  void notify(NotificationParams notificationParams, onSuccessCallback,
      onErrorCallback);
}

class NotificationParams {
  late AtKey atKey;
  String? value;
  OperationEnum? operation;
  MessageTypeEnum? messageType;
  PriorityEnum? priority;
  StrategyEnum? strategy;
  int? latestN;
  String? notifier = SYSTEM;
  bool isDedicated = false;
}
