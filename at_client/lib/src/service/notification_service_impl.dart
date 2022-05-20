import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/util/regex_match_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

class NotificationServiceImpl
    implements NotificationService, AtSignChangeListener {
  final Map<NotificationConfig, StreamController> _streamListeners = {};
  final emptyRegex = '';
  static const notificationIdKey = '_latestNotificationIdv2';
  static final Map<String, NotificationService> _notificationServiceMap = {};

  final _logger = AtSignLogger('NotificationServiceImpl');
  var _isMonitorPaused = false;
  late AtClient _atClient;
  Monitor? _monitor;
  ConnectivityListener? _connectivityListener;
  dynamic _lastMonitorRetried;
  late AtClientManager _atClientManager;

  static Future<NotificationService> create(AtClient atClient,
      {required AtClientManager atClientManager}) async {
    if (_notificationServiceMap.containsKey(atClient.getCurrentAtSign())) {
      return _notificationServiceMap[atClient.getCurrentAtSign()]!;
    }
    final notificationService =
        NotificationServiceImpl._(atClientManager, atClient);
    await notificationService._init();
    _notificationServiceMap[atClient.getCurrentAtSign()!] = notificationService;
    return _notificationServiceMap[atClient.getCurrentAtSign()]!;
  }

  NotificationServiceImpl._(
      AtClientManager atClientManager, AtClient atClient) {
    _atClientManager = atClientManager;
    _atClient = atClient;
    _atClientManager.listenToAtSignChange(this);
  }

  Future<void> _init() async {
    _logger.finer('${_atClient.getCurrentAtSign()} notification service init');
    await _startMonitor();
    _logger.finer(
        '${_atClient.getCurrentAtSign()} monitor status: ${_monitor?.getStatus()}');
    if (_connectivityListener == null) {
      _connectivityListener = ConnectivityListener();
      _connectivityListener!.subscribe().listen((isConnected) {
        if (isConnected) {
          _logger.finer(
              '${_atClient.getCurrentAtSign()} starting monitor through connectivity listener event');
          _startMonitor();
        } else {
          _logger.finer('lost network connectivity');
        }
      });
    }
  }

  Future<void> _startMonitor() async {
    if (_monitor != null && _monitor!.status == MonitorStatus.started) {
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
    if (_monitor!.status == MonitorStatus.started) {
      _isMonitorPaused = false;
    }
  }

  Future<int?> _getLastNotificationTime() async {
    var lastNotificationKeyStr =
        '$notificationIdKey.${_atClient.getPreferences()!.namespace}${_atClient.getCurrentAtSign()}';
    var atKey = AtKey.fromString(lastNotificationKeyStr);
    if (_atClient
        .getLocalSecondary()!
        .keyStore!
        .isKeyExists(lastNotificationKeyStr)) {
      var atValue;
      try {
        atValue = await _atClient.get(atKey);
      } on Exception catch (e) {
        _logger
            .severe('Exception in getting last notification id: ${e.toString}');
      }
      if (atValue != null && atValue.value != null) {
        _logger.finer('json from hive: ${atValue.value}');
        return jsonDecode(atValue.value)['epochMillis'];
      }
      return null;
    }
  }

  @override
  void stopAllSubscriptions() {
    _isMonitorPaused = true;
    _monitor?.stop();
    _connectivityListener?.unSubscribe();
    _streamListeners.forEach((regex, streamController) {
      if (!streamController.isClosed) () => streamController.close();
    });
    _streamListeners.clear();
  }

  Future<void> _internalNotificationCallback(String notificationJSON) async {
    try {
      final notificationParser = NotificationResponseParser();
      final atNotifications = await notificationParser
          .getAtNotifications(notificationParser.parse(notificationJSON));
      for (var atNotification in atNotifications) {
        // Saves latest notification id to the keys if its not a stats notification.
        if (atNotification.id != '-1') {
          await _atClient.put(AtKey()..key = notificationIdKey,
              jsonEncode(atNotification.toJson()));
        }
        _streamListeners.forEach((notificationConfig, streamController) async {
          // Decrypt the value in the atNotification object when below criteria is met.
          if (notificationConfig.shouldDecrypt && atNotification.id != '-1') {
            atNotification.value =
                await _getDecryptedNotifications(atNotification);
          }
          if (notificationConfig.regex != emptyRegex) {
            if (hasRegexMatch(atNotification.key, notificationConfig.regex)) {
              streamController.add(atNotification);
            }
          } else {
            streamController.add(atNotification);
          }
        });
      }
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
      _logger.finer(
          '${_atClient.getCurrentAtSign()} monitor is paused. not retrying');
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
      ..notificationID = notificationParams.id
      ..atKey = notificationParams.atKey;
    try {
      // Notifies key to another notificationParams.atKey.sharedWith atsign
      await _atClient.notifyChange(notificationParams);
    } on Exception catch (e) {
      // Setting notificationStatusEnum to errored
      notificationResult.notificationStatusEnum =
          NotificationStatusEnum.undelivered;
      var atClientException =
          AtClientException(error_codes['AtClientException'], e.toString());
      notificationResult.atClientException = atClientException;
      // Invoke onErrorCallback
      if (onError != null) {
        onError(notificationResult);
      }
      return notificationResult;
    }
    var notificationParser = NotificationResponseParser();
    // Gets the notification status and parse the response.
    var notificationStatus = notificationParser
        .parse(await _getFinalNotificationStatus(notificationParams.id));
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
            error_codes['AtClientException'],
            'Unable to connect to secondary server');
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
    String status = '';
    // For every 2 seconds, queries the status of the notification
    while (status.isEmpty || status == 'data:queued') {
      await Future.delayed(Duration(seconds: 2),
          () async => status = await _atClient.notifyStatus(notificationId));
    }
    return status;
  }

  @override
  Stream<AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    regex ??= emptyRegex;
    if (_streamListeners.containsKey(regex)) {
      _logger.finer('subscription already exists');
      return _streamListeners[regex]!.stream as Stream<AtNotification>;
    }
    final _controller = StreamController<AtNotification>.broadcast();
    _streamListeners[NotificationConfig()
      ..regex = regex
      ..shouldDecrypt = shouldDecrypt] = _controller;
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
      _logger.finer(
          'removing from _notificationServiceMap: ${_atClient.getCurrentAtSign()}');
      _notificationServiceMap.remove(_atClient.getCurrentAtSign());
    }
  }

  MonitorStatus? getMonitorStatus() {
    if (_monitor == null) {
      _logger.severe('${_atClient.getCurrentAtSign()} monitor not initialised');
      return null;
    }
    _logger.finer(
        '${_atClient.getCurrentAtSign()} monitor status: ${_monitor!.getStatus()}');
    return _monitor!.getStatus();
  }

  Future<String?> _getDecryptedNotifications(
      AtNotification atNotification) async {
    // If atNotification value is null or empty, returning the same.
    if (atNotification.value == null || atNotification.value!.isEmpty) {
      return atNotification.value;
    }
    try {
      var atKey = AtKey()
        ..key = atNotification.key
        ..sharedBy = atNotification.from
        ..sharedWith = atNotification.to;
      var decryptionService =
          AtKeyDecryptionManager.get(atKey, atNotification.to);
      var decryptedValue =
          await decryptionService.decrypt(atKey, atNotification.value);
      // Return decrypted value
      return decryptedValue.toString().trim();
    } on Exception catch (e) {
      _logger.severe('unable to decrypt notification value: ${e.toString()}');
    }
    // Returning the encrypted value if the decryption fails
    return atNotification.value!;
  }

  @override
  Future<NotificationResult> getStatus(String notificationId) async {
    var status = await _atClient.notifyStatus(notificationId);
    var atResponse = DefaultResponseParser().parse(status);
    NotificationResult notificationResult;
    // If the Notification Response is error, set the notification status to undelivered
    if (atResponse.isError) {
      return NotificationResult()
        ..notificationID = notificationId
        ..notificationStatusEnum = NotificationStatusEnum.undelivered
        ..atClientException = AtClientException(
            atResponse.errorCode, atResponse.errorDescription);
    }

    notificationResult = NotificationResult()
      ..notificationID = notificationId
      ..notificationStatusEnum =
          _getNotificationStatusEnum(atResponse.response);
    return notificationResult;
  }

  /// Returns the NotificationStatusEnum for the given string of notificationStatus
  NotificationStatusEnum _getNotificationStatusEnum(String notificationStatus) {
    switch (notificationStatus.toLowerCase()) {
      case 'delivered':
        return NotificationStatusEnum.delivered;
      case 'undelivered':
        return NotificationStatusEnum.undelivered;
      default:
        return NotificationStatusEnum.undelivered;
    }
  }
}
