import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/exception/at_client_exception_util.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/connectivity_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/response/at_notification.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

class NotificationServiceImpl
    implements NotificationService, AtSignChangeListener {
  Map<String, StreamController> streamListeners = {};
  final EMPTY_REGEX = '';
  static const notificationIdKey = '_latestNotificationId';
  static final Map<String, NotificationService> _notificationServiceMap = {};

  final _logger = AtSignLogger('NotificationServiceImpl');
  var _isMonitorPaused = false;
  late AtClient _atClient;
  Monitor? _monitor;
  ConnectivityListener? _connectivityListener;
  var _lastMonitorRetried;

  static Future<NotificationService> create(AtClient atClient) async {
    if (_notificationServiceMap.containsKey(atClient.getCurrentAtSign())) {
      return _notificationServiceMap[atClient.getCurrentAtSign()]!;
    }
    final notificationService = NotificationServiceImpl._(atClient);
    await notificationService._init();
    _notificationServiceMap[atClient.getCurrentAtSign()!] = notificationService;
    return _notificationServiceMap[atClient.getCurrentAtSign()]!;
  }

  NotificationServiceImpl._(AtClient atClient) {
    _atClient = atClient;
  }

  Future<void> _init() async {
    _logger.finer('notification init starting monitor');
    await _startMonitor();
    if (_connectivityListener == null) {
      _connectivityListener = ConnectivityListener();
      _connectivityListener!.subscribe().listen((isConnected) {
        if (isConnected) {
          _logger.finer(
              'starting monitor through connectivity listener event');
          _startMonitor();
        } else {
          _logger.finer('lost network connectivity');
        }
      });
    }
  }

  Future<void> _startMonitor() async {
    if (_monitor != null && _monitor!.status == MonitorStatus.Started) {
      _logger.finer(
          'monitor is already started for ${_atClient.getCurrentAtSign()}');
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
    await _monitor!.start(lastNotificationTime: lastNotificationTime);
    if (_monitor!.status == MonitorStatus.Started) {
      _isMonitorPaused = false;
    }
  }

  Future<int?> _getLastNotificationTime() async {
    final atValue = await _atClient.get(AtKey()..key = notificationIdKey);
    if (atValue.value != null) {
      _logger.finer('json from hive: ${atValue.value}');
      return jsonDecode(atValue.value)['epochMillis'];
    }
    return null;
  }

  void stopAllSubscriptions() {
    _isMonitorPaused = true;
    _monitor?.stop();
    _connectivityListener?.unSubscribe();
    streamListeners.forEach((regex, streamController) {
      if (!streamController.isClosed) () => streamController.close();
    });
    streamListeners.clear();
  }

  void _internalNotificationCallback(String notificationJSON) async {
    try {
      final notificationParser = NotificationResponseParser();
      final atNotifications = notificationParser
          .getAtNotifications(notificationParser.parse(notificationJSON));
      atNotifications.forEach((atNotification) async {
        // Saves latest notification id to the keys if its not a stats notification.
        if (atNotification.id != '-1') {
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
    if (_lastMonitorRetried != null &&
        DateTime.now().toUtc().difference(_lastMonitorRetried).inSeconds < 15) {
      _logger.info('Attempting to retry in less than 15 seconds... Rejected');
      return;
    }
    if (_isMonitorPaused) {
      _logger.finer('monitor is paused. not retrying');
      return;
    }
    _lastMonitorRetried = DateTime.now().toUtc();
    _logger.finer('monitor retry for ${_atClient.getCurrentAtSign()}');
    Future.delayed(
        Duration(seconds: 15),
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
    var notificationParser = NotificationResponseParser();
    notificationResult.notificationID =
        notificationParser.parse(notificationId).response;
    // Gets the notification status and parse the response.
    var notificationStatus = notificationParser.parse(
        await _getFinalNotificationStatus(notificationResult.notificationID!));
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
    return _controller.stream;
  }

  @override
  void listenToAtSignChange(SwitchAtSignEvent switchAtSignEvent) {
    if (switchAtSignEvent.previousAtClient?.getCurrentAtSign() ==
        _atClient.getCurrentAtSign()) {
      // actions for previous atSign
      _logger.finer(
          'stopping notification listeners for ${_atClient.getCurrentAtSign()}');
      stopAllSubscriptions();
    }
  }
}
