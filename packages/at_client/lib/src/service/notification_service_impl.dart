import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/listener/at_sign_change_listener.dart';
import 'package:at_client/src/listener/switch_at_sign_event.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/regex_match_util.dart';
import 'package:at_commons/at_builders.dart';
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
  static const lastReceivedNotificationKey = 'lastReceivedNotification';

  final _logger = AtSignLogger('NotificationServiceImpl');

  /// Controls whether or not the monitor is actually running.
  /// * monitorIsPaused is initially set to true (monitor should not be running)
  /// * it is set to false when [_startMonitor] is called (monitor should be running)
  /// * and it is set to true when [stopAllSubscriptions] is called (monitor should not be running).
  /// ( Note that stopAllSubscriptions also calls Monitor.stop() )
  @visibleForTesting
  var monitorIsPaused = true;

  late AtClient _atClient;
  Monitor? _monitor;
  ConnectivityListener? _connectivityListener;

  late AtClientManager _atClientManager;
  AtClientValidation atClientValidation = AtClientValidation();
  late AtKeyEncryptionManager atKeyEncryptionManager;

  /// The delay between when a call is made to monitorRetry() - i.e. a monitorRestart is queued -
  /// and when Monitor.start() is subsequently called
  Duration monitorRetryInterval = Duration(seconds: 5);

  @visibleForTesting
  late AtKey lastReceivedNotificationAtKey;

  /// If false, is set to true when [monitorRetry] is called.
  /// If true, remains true when [monitorRetry] is called.
  /// Is reset to false when [monitorRetry] actually calls Monitor.start
  @visibleForTesting
  bool monitorRestartQueued = false;

  /// Number of times the [monitorRetry] function has been called
  @visibleForTesting
  int callsToMonitorRetry = 0;

  /// Number of times [monitorRetry] has actually called [Monitor.start]. Note that when [monitorRetry]
  /// is called, it will not queue a call to [Monitor.start] if [monitorRestartQueued] is true
  @visibleForTesting
  int monitorRetryCallsToMonitorStart = 0;

  /// Returns the currentAtSign associated with the NotificationService
  String get currentAtSign => _atClient.getCurrentAtSign()!;

  static Future<NotificationService> create(AtClient atClient,
      {required AtClientManager atClientManager, Monitor? monitor}) async {
    final notificationService = NotificationServiceImpl._(atClientManager, atClient, monitor: monitor);
    // We used to call _init() at this point which would start the monitor, but now we
    // call _init() from the [subscribe] method
    return notificationService;
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
            monitorRetry);
    _atClientManager.listenToAtSignChange(this);
    lastReceivedNotificationAtKey = AtKey.local(lastReceivedNotificationKey,
            _atClientManager.atClient.getCurrentAtSign()!,
            namespace: _atClientManager.atClient.getPreferences()!.namespace)
        .build();
    atKeyEncryptionManager = AtKeyEncryptionManager(_atClient);
  }

  /// Simple state to prevent _init() running more than once *concurrently*
  bool _initializing = false;

  Future<void> _init() async {
    // Note that it is safe to call _init() more than once, sequentially, because it only does two things,
    // and both of those things are safe guarded:
    // (1) calls _startMonitor() - which won't do anything if the monitor is already started
    // (2) creates a connectivity listener and subscription - but only if _connectivityListener is currently null
    if (_initializing) {
      return;
    }
    try {
      _initializing = true;
      _logger.finer('${_atClient.getCurrentAtSign()} notification service _init()');
      await _startMonitor();
      _logger.finer(
          '${_atClient.getCurrentAtSign()} monitor status: ${_monitor?.getStatus()}');
      if (_connectivityListener == null) {
        _connectivityListener = ConnectivityListener();
        // Note that this subscription is cancelled by stopAllSubscriptions(), so we don't need to worry
        // about this subscription accidentally starting the monitor after it has been intentionally stopped,
        // for example by switching atSigns
        _connectivityListener!.subscribe().listen((isConnected) {
          if (isConnected) {
            _logger.finer('${_atClient.getCurrentAtSign()} starting monitor through connectivity listener event');
            _startMonitor();
          } else {
            _logger.finer('lost network connectivity');
          }
        });
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _startMonitor() async {
    monitorIsPaused = false;

    if (_monitor != null && _monitor!.status == MonitorStatus.started) {
      _logger.finer(
          'monitor is already started for ${_atClient.getCurrentAtSign()}');
      return;
    }

    int? lastNotificationTime;
    try {
      lastNotificationTime = await getLastNotificationTime();
    } catch (e) {
      _logger.warning('${_atClient.getCurrentAtSign()}: startMonitor(): getLastNotificationTime() failed : $e');
      return;
    }

    try {
      await _monitor!.start(lastNotificationTime: lastNotificationTime);
    } catch (e) {
      _logger.warning('${_atClient.getCurrentAtSign()}: startMonitor(): Failed to start monitor : $e');
      return;
    }
  }

  /// Return the last received notification DateTime in epochMillis when
  /// [AtClientPreference.fetchOfflineNotifications] is set true.
  ///
  /// Returns null when the key which holds the lastNotificationReceived
  /// does not exist.
  @visibleForTesting
  Future<int?> getLastNotificationTime() async {
    if (_atClientManager.atClient.getPreferences()!.fetchOfflineNotifications ==
        false) {
      // fetchOfflineNotifications == false means issue `monitor` command without a lastNotificationTime
      // which will result in the server not sending any previously received notifications
      return null;
    }

    // fetchOfflineNotifications == true (the default) means we want all notifications since the last one we received
    // We keep track of the last notification id in the client-side key store
    // Check if the new key (local:lastNotificationReceived@alice) is available in the keystore.
    // If yes, fetch the value;
    AtValue? atValue;
    if (_atClient
        .getLocalSecondary()!
        .keyStore!
        .isKeyExists(lastReceivedNotificationAtKey.toString())) {
      atValue = await _atClient.get(lastReceivedNotificationAtKey);
    }
    // If new key does not exist or value is null, check for the old key (_latestNotificationIdv2@alice)
    // If old key exist, fetch the value and update the new key with old key's value
    if (atValue == null || atValue.value == null) {
      var lastNotificationKeyStr =
          '$notificationIdKey.${_atClient.getPreferences()!.namespace}${_atClient.getCurrentAtSign()}';
      var atKey = AtKey.fromString(lastNotificationKeyStr);
      if (_atClient
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(lastNotificationKeyStr)) {
        try {
          atValue = await _atClient.get(atKey);
          await _atClient.put(lastReceivedNotificationAtKey, atValue.value);
        } on Exception catch (e) {
          _logger.severe(
              'Exception in getting last notification id: ${e.toString}');
        }
      }
    }
    if (atValue?.value != null) {
      _logger.finer('json from hive: ${atValue?.value}');
      return jsonDecode(atValue?.value)['epochMillis'];
    }
    return null;
  }

  @override
  void stopAllSubscriptions() {
    _logger.finer('stopAllSubscriptions() called - setting monitorIsPaused to true');
    monitorIsPaused = true;
    _monitor?.stop();
    _connectivityListener?.unSubscribe();
    _connectivityListener = null;
    _streamListeners.forEach((regex, streamController) {
      if (!streamController.isClosed) () => streamController.close();
    });
    _streamListeners.clear();
  }

  Future<void> _internalNotificationCallback(String notificationJSON) async {
    try {
      _logger.finest('DEBUG: $notificationJSON');

      final notificationParser = NotificationResponseParser();
      final atNotifications = await notificationParser
          .getAtNotifications(notificationParser.parse(notificationJSON));
      for (var atNotification in atNotifications) {
        // Saves latest notification id to the keys if its not a stats notification.
        if (atNotification.id != '-1') {
          await _atClient.put(lastReceivedNotificationAtKey,
              jsonEncode(atNotification.toJson()));
        }
        _streamListeners.forEach((notificationConfig, streamController) async {
          try {
            var transformedNotification =
                await NotificationResponseTransformer(_atClient)
                    .transform(Tuple()
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

  @visibleForTesting
  /// Called by [NotificationServiceImpl]'s Monitor when the Monitor has detected that it (the Monitor) has
  /// failed and needs to be retried.
  /// * Returns _true_ if a call to Monitor.start() has been queued, _false_ otherwise.
  ///
  /// Behaviour:
  /// * Increments [callsToMonitorRetry] every time it is called.
  /// * First check - if there is a retry already 'in progress' - i.e. [monitorRestartQueued] is true - then return _false_
  /// * Second check - if monitor has been paused, then retries should not happen, so return _false_
  /// * If there is not a retry already 'in progress' - i.e. [monitorRestartQueued] is false - then
  ///   * set monitorRestartQueued to true
  ///   * create a delayed future which will execute after [monitorRetryInterval] which will
  ///     * set monitorRestartQueued to false
  ///     * Increment [monitorRetryCallsToMonitorStart]
  ///     * call monitor.start()
  ///   * return _true_
  bool monitorRetry() {
    callsToMonitorRetry++;
    if (monitorRestartQueued) {
      _logger.info('Monitor retry already queued');
      return false;
    }
    if (monitorIsPaused) {
      _logger.finer(
          '${_atClient.getCurrentAtSign()} monitor is paused. not retrying');
      return false;
    }
    monitorRestartQueued = true;
    _logger.finer('monitor retry for ${_atClient.getCurrentAtSign()}');
    Future.delayed(monitorRetryInterval, () async {
      monitorRestartQueued = false;
      if (monitorIsPaused) { // maybe it's been paused during the time since the retry was requested
        _logger.warning("monitorRetry() will NOT call Monitor.start() because we've stopped all subscriptions");
      } else {
        monitorRetryCallsToMonitorStart++;
        await _monitor!.start(lastNotificationTime: await getLastNotificationTime());
        // Note we do not need to handle exceptions as Monitor.start handles all of them.
        // Additionally, we do not need to queue another monitor retry, since Monitor.start
        // will call this function (_monitorRetry) if required
      }
    });
    return true;
  }

  void _onMonitorError(Exception e) {
    _logger.severe('internal error in monitor: ${e.toString()}');
  }

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {bool waitForFinalDeliveryStatus = true, // this was the behaviour before introducing this parameter
      bool checkForFinalDeliveryStatus = true, // this was the behaviour before introducing this parameter
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
        unawaited(_waitForAndHandleFinalNotificationSendStatus(
            notificationParams, notificationResult, onSuccess, onError));
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
    _logger.finer('subscribe(regex: $regex, shouldDecrypt: $shouldDecrypt');
    regex ??= emptyRegex;
    var notificationConfig = NotificationConfig()
      ..regex = regex
      ..shouldDecrypt = shouldDecrypt;
    var atNotificationStream = _streamListeners.putIfAbsent(
        notificationConfig, () => StreamController<AtNotification>.broadcast());

    // Temporary fix for https://github.com/atsign-foundation/at_client_sdk/issues/770
    //     (Temporary because it's a bit of a kludge, but the proper fix requires the implementation
    //      of enhancements to the monitor verb which allow for multiple subscriptions, and changes
    //      to this service and to the Monitor to make use of that enhancement.)
    // Previously we were initializing the notification service
    // before there were any 'real' subscriptions
    // and because the notification service currently starts the monitor
    // without any regex, the monitor immediately starts to stream all notifications
    //
    // As a result, if there is even a very short delay between when the notification service
    // is created and when the app calls 'subscribe', then the app will 'miss'
    // those notifications.
    //
    // So - for now, if the subscription is 'statsNotification', then we will delay
    // initialization of the service until when the app does a real 'subscribe' call.
    //
    // Normally, the app code will call subscribe which will
    // start the monitor, and SyncService will start receiving statsNotifications.
    // However, if the app isn't explicitly calling 'sync', and hasn't called subscribe(),
    // then there will be a delay of 30 seconds before the monitor is started, the first
    // statsNotification message is received, and a sync request is queued.
    // In order to compensate for that, the SyncServiceImpl itself now queues a sync request
    // when it is initialized.
    if (regex == 'statsNotification') {
      Future.delayed(Duration(seconds: 30), () async => _init());
    } else {
      _init();
    }
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
    _atClientManager.removeChangeListeners(this);

    _logger.finer('stopping notification listeners for ${_atClient.getCurrentAtSign()}');
    stopAllSubscriptions();
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
