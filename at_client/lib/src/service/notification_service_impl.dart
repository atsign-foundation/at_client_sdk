import 'dart:async';
import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/src/responseParser/notification_response_parser.dart';

class NotificationServiceImpl implements NotificationService {
  Map<String, Function> listeners = {};
  Map<String, StreamController> streamListeners = {};
  final EMPTY_REGEX = '';
  static const notificationIdKey = '_latestNotificationId';

  final _logger = AtSignLogger('NotificationServiceImpl');

  late AtClient atClient;

  bool isMonitorStarted = false;
  late Monitor _monitor;

  NotificationServiceImpl(AtClient atClient) {
    this.atClient = atClient;
  }

  void _init() {
    if (!isMonitorStarted) {
      _logger
          .finer('starting monitor for atsign: ${atClient.getCurrentAtSign()}');
      _startMonitor();
    }
  }

  Future<void> _startMonitor() async {
    final lastNotificationTime = await _getLastNotificationTime();
    _monitor = Monitor(
        _internalNotificationCallback,
        _onMonitorError,
        atClient.getCurrentAtSign()!,
        atClient.getPreferences()!,
        MonitorPreference()..keepAlive = true,
        _monitorRetry);
    _logger.finer(
        'starting monitor with last notification time: $lastNotificationTime');
    await _monitor.start(lastNotificationTime: lastNotificationTime);
    isMonitorStarted = true;
  }

  Future<int?> _getLastNotificationTime() async {
    final atValue = await atClient.get(AtKey()..key = notificationIdKey);
    if (atValue.value != null) {
      _logger.finer('json from hive: ${atValue.value}');
      return jsonDecode(atValue.value)['epochMillis'];
    }
    return null;
  }

  @override
  void listen(Function notificationCallback, {String? regex}) {
    _init();
    regex ??= EMPTY_REGEX;
    listeners[regex] = notificationCallback;
    _logger.finer('added regex to listener $regex');
  }

  void stop() {
    _monitor.stop();
  }

  void _internalNotificationCallback(String notificationJSON) async {
    // #TODO move some of this logic to notification parser
    var notifications = notificationJSON.split('notification: ');
    notifications.forEach((notification) async {
      if (notification.isEmpty) {
        _logger.finer('empty string in notification');
        return;
      }
      notification = notification.replaceFirst('notification:', '');
      notification = notification.trim();
      final atNotification = AtNotification.fromJson(jsonDecode(notification));
      await atClient.put(AtKey()..key = notificationIdKey, notification);
      listeners.forEach((regex, subscriptionCallback) {
        if (regex != EMPTY_REGEX) {
          final isMatches = regex.allMatches(atNotification.key).isNotEmpty;
          if (isMatches) {
            subscriptionCallback(atNotification);
          }
        } else {
          subscriptionCallback(atNotification);
        }
      });
      streamListeners.forEach((regex, streamController) {
        if (regex != EMPTY_REGEX) {
          final isMatches = regex.allMatches(atNotification.key).isNotEmpty;
          if (isMatches) {
            streamController.add(atNotification);
          }
        } else {
          streamController.add(atNotification);
        }
      });
    });
  }

  void _monitorRetry() {
    _logger.finer('monitor retry');
    Future.delayed(
        Duration(seconds: 5),
        () async => _monitor.start(
            lastNotificationTime: await _getLastNotificationTime()));
  }

  void _onMonitorError() {
    //#TODO implement
  }

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {Function? onSuccess, Function? onError}) async {
    var notificationResult = NotificationResult()
      ..atKey = notificationParams.atKey;
    var notificationId;
    try {
      // Notifies key to another notificationParams.atKey.sharedWith atsign
      // Returns the notificationId.
      notificationId = await atClient.notifyChange(notificationParams);
    } on Exception catch (e) {
      // Setting notificationStatusEnum to errored
      notificationResult.notificationStatusEnum =
          NotificationStatusEnum.errored;
      var errorCode = AtClientExceptionUtil.getErrorCode(e);
      var atClientException = AtClientException(
          errorCode, AtClientExceptionUtil.getErrorDescription(errorCode));
      notificationResult.atClientException = atClientException;
      // Invoke onErrorCallback
      if (onError != null) {
        onError(notificationResult);
      }
      return notificationResult;
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
        // If onSuccess callback is registered, invoke callback method.
        if (onSuccess != null) {
          onSuccess(notificationResult);
        }
        break;
      case NotificationStatusEnum.errored:
        notificationResult.notificationStatusEnum =
            NotificationStatusEnum.errored;
        notificationResult.atClientException = AtClientException(
            error_codes['SecondaryConnectException'],
            error_description[error_codes['SecondaryConnectException']]);
        // If onError callback is registered, invoke callback method.
        if (onError != null) {
          onError(notificationResult);
        }
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

  @override
  Stream<AtNotification> subscribe({String? regex}) {
    _init();
    regex ??= EMPTY_REGEX;
    final _controller = StreamController<AtNotification>();
    streamListeners[regex] = _controller;
    _logger.finer('added regex to listener $regex');
    return _controller.stream;
  }
}

/// [NotificationResult] encapsulates the notification response
class NotificationResult {
  String? notificationID;
  late AtKey atKey;
  late NotificationStatusEnum notificationStatusEnum;
  AtClientException? atClientException;

  @override
  String toString() {
    return 'key: ${atKey.key} sharedWith: ${atKey.sharedWith} status: $notificationStatusEnum';
  }
}

class AtNotification {
  late String notificationId;
  late String key;
  late int epochMillis;

  static AtNotification fromJson(Map json) {
    return AtNotification()
      ..notificationId = json['id']
      ..key = json['key']
      ..epochMillis = json['epochMillis'];
  }

  Map toJson() {
    final jsonMap = {};
    jsonMap['id'] = notificationId;
    jsonMap['key'] = key;
    jsonMap['epochMillis'] = epochMillis;
    return jsonMap;
  }

  @override
  String toString() {
    return 'AtNotification{notificationId: $notificationId, key: $key, epochMillis: $epochMillis}';
  }
}
