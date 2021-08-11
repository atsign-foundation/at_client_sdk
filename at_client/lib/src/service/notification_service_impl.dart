import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/responseParser/notification_response_parser.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class NotificationServiceImpl implements NotificationService {
  Map<String, NotificationService> instances = {};
  Map<String, Function> listeners = {};
  final EMPTY_REGEX = '';
  static const notificationIdKey = '_latestNotificationId';

  late AtClient atClient;

  NotificationService? getInstance() {
    _startMonitor();
    return instances[atClient.getCurrentAtSign()];
  }

  NotificationServiceImpl(this.atClient);

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
    if (atValue != null) {
      return int.parse(atValue.value);
    }
    return null;
  }

  @override
  void listen(Function notificationCallback, {String? regex}) {
    regex ??= EMPTY_REGEX;
    listeners[regex] = notificationCallback;
  }

  void _internalNotificationCallback(String notificationJSON) {
    final atNotification =
        AtNotification.fromJson(jsonDecode(notificationJSON));
    atClient.put(
        AtKey()..key = notificationIdKey, atNotification.notificationId);
    listeners.forEach((regex, subscriptionCallback) {
      final isMatches = regex.allMatches(atNotification.key).isNotEmpty;
      if (isMatches) {
        subscriptionCallback(atNotification);
      }
    });
  }

  void _onMonitorError() {
    //#TODO implement
  }

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      onSuccessCallback, onErrorCallback) async {
    var notificationResult;
    var notificationId;
    try {
      notificationResult = NotificationResult()
        ..atKey = notificationParams.atKey;
      // Notifies key to another notificationParams.atKey.sharedWith atsign
      // Returns the notificationId.
      notificationId = await atClient.notifyChange(notificationParams);
    } on AtLookUpException catch (e) {
      notificationResult.notificationStatusEnum =
          NotificationStatusEnum.errored;
      var errorCode = AtClientExceptionUtil.getErrorCode(e);
      var atClientException = AtClientException(
          errorCode, AtClientExceptionUtil.getErrorDescription(errorCode));
      notificationResult.atClientException = atClientException;
      onErrorCallback(notificationResult);
      throw atClientException;
    }
    notificationId = notificationId.replaceAll('data:', '');
    notificationResult.notificationID = notificationId;

    // Gets the notification status and parse the response.
    var notificationStatus = ResponseParser.parseNotificationResponse(
        await _getFinalNotificationStatus(notificationId));

    switch (notificationStatus) {
      case NotificationStatusEnum.delivered:
        notificationResult.notificationStatusEnum =
            NotificationStatusEnum.delivered;
        onSuccessCallback(notificationResult);
        break;
      case NotificationStatusEnum.errored:
        notificationResult.notificationStatusEnum =
            NotificationStatusEnum.errored;
        notificationResult.atClientException = AtClientException(
            error_codes['SecondaryConnectException'],
            error_description[error_codes['SecondaryConnectException']]);
        onErrorCallback(notificationResult);
        break;
    }
    return notificationResult;
  }

  /// Queries the status of the notification
  /// Takes the notificationId as input as returns the status of the notification
  Future<String> _getFinalNotificationStatus(String notificationId) async {
    var status;
    // For every 2 seconds, queries the status of the notification
    while (status == null || status == 'data:queued') {
      await Future.delayed(Duration(seconds: 2),
          () async => status = await atClient.notifyStatus(notificationId));
    }
    return status;
  }
}

class NotificationResult {
  String? notificationID;
  late AtKey atKey;
  late NotificationStatusEnum notificationStatusEnum;
  AtClientException? atClientException;

  @override
  String toString() {
    return 'key: ${atKey.key} status: $notificationStatusEnum';
  }
}

class AtNotification {
  late int notificationId;
  late String key;
  dynamic? value;

  static AtNotification fromJson(Map json) {
    //#TODO complete impl
    return AtNotification();
  }

  static Map toJson(AtNotification notification) {
    //#TODO complete impl
    final jsonMap = {};
    return jsonMap;
  }
}
