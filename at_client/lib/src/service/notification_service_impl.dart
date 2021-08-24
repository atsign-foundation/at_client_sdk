import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/service/connectivity_listener.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

class NotificationServiceImpl implements NotificationService, AtSignChangeListener {
  Map<String, Function> listeners = {};
  Map<String, StreamController> streamListeners = {};
  final EMPTY_REGEX = '';
  static const notificationIdKey = '_latestNotificationId';

  final _logger = AtSignLogger('NotificationServiceImpl');

  late AtClient _atClient;

  bool _isMonitorStarted = false;
  Monitor? _monitor;
  ConnectivityListener? _connectivityListener;

  NotificationServiceImpl(AtClient atClient) {
    this._atClient = atClient;
  }

  void _init() {
    if (_connectivityListener == null) {
      _connectivityListener = ConnectivityListener();
      _connectivityListener!.subscribe().listen((isConnected) {
        if (isConnected) {
          _logger.finer(
              'starting monitor for atsign: ${_atClient.getCurrentAtSign()}');
          _startMonitor();
        } else {
          _logger.finer('lost network connectivity');
        }
      });
    }
  }

  Future<void> _startMonitor() async {
    if (_isMonitorStarted) {
      _logger.finer('monitor is already started');
      return;
    }
    final lastNotificationTime = await _getLastNotificationTime();
    _monitor = Monitor(
        _internalNotificationCallback,
        _onMonitorError,
        _atClient.getCurrentAtSign()!,
        _atClient.getPreferences()!,
        MonitorPreference()..keepAlive = true,
        _monitorRetry);
    _logger.finer(
        'starting monitor with last notification time: $lastNotificationTime');
    await _monitor!.start(lastNotificationTime: lastNotificationTime);
    _isMonitorStarted = true;
  }

  Future<int?> _getLastNotificationTime() async {
    final atValue = await _atClient.get(AtKey()..key = notificationIdKey);
    if (atValue.value != null) {
      _logger.finer('json from hive: ${atValue.value}');
      return jsonDecode(atValue.value)['epochMillis'];
    }
    return null;
  }

  void stop() {
    _monitor?.stop();
    _connectivityListener?.unSubscribe();
  }

  void _internalNotificationCallback(String notificationJSON) async {
    try {
      final notificationParser = NotificationResponseParser();
      final atNotifications = notificationParser
          .getAtNotifications(notificationParser.parse(notificationJSON));
      atNotifications.forEach((atNotification) async {
        // Saves latest notification id to the keys if its not a stats notification.
        if (atNotification.notificationId != '-1') {
          await _atClient.put(AtKey()..key = notificationIdKey,
              jsonEncode(atNotification.toJson()));
        }
        streamListeners.forEach((regex, streamController) {
          if (regex != EMPTY_REGEX) {
            if (regex.allMatches(atNotification.key).isNotEmpty) {
              streamController.add(atNotification);
            }
          } else {
            streamController.add(atNotification);
          }
        });
      });
    } on Exception catch (e) {
      _logger.severe(
          'exception processing: error:${e.toString()} notificationJson: $notificationJSON');
    }
  }

  void _monitorRetry() {
    _logger.finer('monitor retry');
    Future.delayed(
        Duration(seconds: 5),
        () async => _monitor!
            .start(lastNotificationTime: await _getLastNotificationTime()));
  }

  void _onMonitorError(Exception e) {
    _logger.severe('internal error in monitor: ${e.toString()}');
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
      notificationId = await _atClient.notifyChange(notificationParams);
    } on Exception catch (e) {
      // Setting notificationStatusEnum to errored
      notificationResult.notificationStatusEnum =
          NotificationStatusEnum.undelivered;
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
    var notificationStatus = NotificationResponseParser()
        .parse(await _getFinalNotificationStatus(notificationId));
    switch (notificationStatus.response) {
      case 'delivered':
        notificationResult.notificationStatusEnum =
            NotificationStatusEnum.delivered;
        // If onSuccess callback is registered, invoke callback method.
        if (onSuccess != null) {
          onSuccess(notificationResult);
        }
        break;
      case 'undelivered':
        notificationResult.notificationStatusEnum =
            NotificationStatusEnum.undelivered;
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
          () async => status = await _atClient.notifyStatus(notificationId));
    }
    return status;
  }

  @override
  Stream<AtNotification> subscribe({String? regex}) {
    regex ??= EMPTY_REGEX;
    final _controller = StreamController<AtNotification>();
    streamListeners[regex] = _controller;
    _logger.finer('added regex to listener $regex');
    _init();
    return _controller.stream;
  }

  @override
  void listenToAtSignChange(AtClient atClient) {
    stop();
    _atClient = atClient;
  }
}

/// [NotificationResult] encapsulates the notification response
class NotificationResult {
  String? notificationID;
  late AtKey atKey;
  NotificationStatusEnum notificationStatusEnum =
      NotificationStatusEnum.undelivered;

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
  String? value;

  static AtNotification fromJson(Map json) {
    return AtNotification()
      ..notificationId = json['id']
      ..key = json['key']
      ..epochMillis = json['epochMillis']
      ..value = json['value'];
  }

  Map toJson() {
    final jsonMap = {};
    jsonMap['id'] = notificationId;
    jsonMap['key'] = key;
    jsonMap['epochMillis'] = epochMillis;
    jsonMap['value'] = value;
    return jsonMap;
  }

  @override
  String toString() {
    return 'AtNotification{id: $notificationId, key: $key, epochMillis: $epochMillis, value: $value}';
  }
}

enum NotificationStatusEnum { delivered, undelivered }
