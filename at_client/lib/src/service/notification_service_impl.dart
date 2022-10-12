import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/listener/connectivity_listener.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/regex_match_util.dart';
import 'package:at_client/src/response/at_notification.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    as at_persistence_secondary_server;
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

class NotificationServiceImpl
    implements NotificationService, AtSignChangeListener {
  final Map<NotificationConfig, StreamController> _streamListeners =
      HashMap(equals: _compareNotificationConfig, hashCode: _generateHashCode);
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
  AtClientValidation atClientValidation = AtClientValidation();
  AtKeyEncryptionManager atKeyEncryptionManager = AtKeyEncryptionManager();

  static Future<NotificationService> create(AtClient atClient,
      {required AtClientManager atClientManager, Monitor? monitor}) async {
    if (_notificationServiceMap.containsKey(atClient.getCurrentAtSign())) {
      return _notificationServiceMap[atClient.getCurrentAtSign()]!;
    }
    final notificationService =
        NotificationServiceImpl._(atClientManager, atClient, monitor: monitor);
    await notificationService._init();
    _notificationServiceMap[atClient.getCurrentAtSign()!] = notificationService;
    return _notificationServiceMap[atClient.getCurrentAtSign()]!;
  }

  NotificationServiceImpl._(AtClientManager atClientManager, AtClient atClient,
      {Monitor? monitor}) {
    _atClientManager = atClientManager;
    _atClient = atClient;
    _monitor = monitor ??
        Monitor(
            _internalNotificationCallback,
            _onMonitorError,
            _atClient.getCurrentAtSign()!,
            _atClient.getPreferences()!,
            MonitorPreference()..keepAlive = true,
            _monitorRetry);
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
    if (AtClientManager.getInstance()
        .atClient
        .getPreferences()!
        .fetchOfflineNotifications) {
      final lastNotificationTime = await _getLastNotificationTime();
      await _monitor!.start(lastNotificationTime: lastNotificationTime);
    } else {
      await _monitor!.start();
    }

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
      AtValue? atValue;
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
    }
    return null;
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
          try {
            var transformedNotification =
                await NotificationResponseTransformer().transform(Tuple()
                  ..one = atNotification
                  ..two = notificationConfig);

            if (notificationConfig.regex != emptyRegex) {
              if (hasRegexMatch(atNotification.key, notificationConfig.regex)) {
                streamController.add(transformedNotification);
              }
            } else {
              streamController.add(transformedNotification);
            }
          } on AtException catch (e) {
            _logger.severe(e.getTraceMessage());
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
      {bool waitForFinalDeliveryStatus =
          true, // this was the behaviour before introducing this parameter
      bool checkForFinalDeliveryStatus =
          true, // this was the behaviour before introducing this parameter
      Function(NotificationResult)? onSuccess,
      Function(NotificationResult)? onError,
      Function(NotificationResult)? onSentToSecondary}) async {
    var notificationResult = NotificationResult()
      ..notificationID = notificationParams.id
      ..atKey = notificationParams.atKey;
    try {
      // If sharedBy atSign is null, default to current atSign.
      if (notificationParams.atKey.sharedBy.isNull) {
        notificationParams.atKey.sharedBy = _atClient.getCurrentAtSign();
      }
      // Append '@' if not already set.
      AtUtils.formatAtSign(notificationParams.atKey.sharedBy!);
      // validate notification request
      await atClientValidation.validateNotificationRequest(
          _atClientManager.secondaryAddressFinder!,
          notificationParams,
          _atClient.getPreferences()!);
      // Get the EncryptionInstance to encrypt the data.
      var atKeyEncryption = atKeyEncryptionManager.get(
          notificationParams.atKey, _atClient.getCurrentAtSign()!);
      // Get the NotifyVerbBuilder from NotificationParams
      var builder = await NotificationRequestTransformer(
              _atClient.getCurrentAtSign()!,
              _atClient.getPreferences()!,
              atKeyEncryption)
          .transform(notificationParams);

      // Run the notify verb on the remote secondary instance.
      await _atClient.getRemoteSecondary()?.executeVerb(builder);
      if (onSentToSecondary != null) {
        onSentToSecondary(notificationResult);
      }
    } on AtException catch (e) {
      // Setting notificationStatusEnum to errored
      notificationResult.notificationStatusEnum =
          NotificationStatusEnum.undelivered;
      notificationResult.atClientException =
          AtExceptionManager.createException(e);
      // Invoke onErrorCallback
      if (onError != null) {
        onError(notificationResult);
      }
    }
    if (!checkForFinalDeliveryStatus) {
      // don't do polling if we don't need to
      return notificationResult;
    } else {
      if (waitForFinalDeliveryStatus) {
        await _waitForAndHandleFinalNotificationSendStatus(
            notificationParams, notificationResult, onSuccess, onError);
        return notificationResult;
      } else {
        // no wait? no await
        _waitForAndHandleFinalNotificationSendStatus(
            notificationParams, notificationResult, onSuccess, onError);
        return notificationResult;
      }
    }
  }

  Future<void> _waitForAndHandleFinalNotificationSendStatus(
      NotificationParams notificationParams,
      NotificationResult notificationResult,
      Function? onSuccess,
      Function? onError) async {
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
  }

  /// Queries the status of the notification
  /// Takes the notificationId as input as returns the status of the notification
  Future<String> _getFinalNotificationStatus(String notificationId) async {
    String status = '';
    bool firstCheck = true;
    // For every 2 seconds, queries the status of the notification
    while (status.isEmpty || status == 'data:queued') {
      if (firstCheck) {
        await Future.delayed(Duration(milliseconds: 500));
        firstCheck = false;
      } else {
        await Future.delayed(Duration(seconds: 2));
      }
      status = await _atClient.notifyStatus(notificationId);
    }
    return status;
  }

  @override
  Stream<AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    regex ??= emptyRegex;
    var notificationConfig = NotificationConfig()
      ..regex = regex
      ..shouldDecrypt = shouldDecrypt;
    var atNotificationStream = _streamListeners.putIfAbsent(
        notificationConfig, () => StreamController<AtNotification>.broadcast());
    return atNotificationStream.stream as Stream<AtNotification>;
  }

  /// Ensures that distinct [NotificationConfig.regex] exists in the key
  /// Compares the [NotificationConfig] object with [NotificationConfig.regex]
  /// If regex's are equals, returns true; else false.
  static bool _compareNotificationConfig(NotificationConfig notificationConfig1,
      NotificationConfig notificationConfig2) {
    if (notificationConfig1.regex == notificationConfig2.regex) {
      return true;
    }
    return false;
  }

  /// Returns the hashcode for the [NotificationConfig.regex]
  static int _generateHashCode(NotificationConfig notificationConfig) {
    return notificationConfig.regex.hashCode;
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

  ///Not a part of API. Exposed for unit test
  @visibleForTesting
  getStreamListenersCount() {
    return _streamListeners.length;
  }

  @override
  Future<AtNotification> fetch(String notificationId) async {
    var notifyFetchVerbBuilder = NotifyFetchVerbBuilder()
      ..notificationId = notificationId;
    String? atNotificationStr;
    try {
      atNotificationStr = await _atClient
          .getRemoteSecondary()
          ?.executeVerb(notifyFetchVerbBuilder);
    } on AtException catch (e) {
      throw AtExceptionManager.createException(e);
    }
    if (atNotificationStr == null) {
      throw AtClientException.message('Failed to fetch the notification id',
          intent: Intent.remoteVerbExecution,
          exceptionScenario: ExceptionScenario.remoteVerbExecutionFailed);
    }
    AtResponse atResponse = DefaultResponseParser().parse(atNotificationStr);
    var atNotificationMap = jsonDecode(atResponse.response);
    if (atNotificationMap['notificationStatus'] ==
        at_persistence_secondary_server.NotificationStatus.expired.toString()) {
      return AtNotification.empty()
        ..id = atNotificationMap['id']
        ..status = atNotificationMap['notificationStatus'];
    }
    return AtNotification.empty()
      ..id = atNotificationMap['id']
      ..key = atNotificationMap['notification']
      ..from = atNotificationMap['fromAtSign']
      ..to = atNotificationMap['toAtSign']
      ..epochMillis = DateTime.parse(atNotificationMap['notificationDateTime'])
          .millisecondsSinceEpoch
      ..status = atNotificationMap['notificationStatus']
      ..value = atNotificationMap['atValue']
      ..operation = atNotificationMap['opType']
      ..messageType = atNotificationMap['messageType'];
  }
}
