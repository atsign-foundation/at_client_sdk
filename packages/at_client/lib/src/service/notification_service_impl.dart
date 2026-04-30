import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart' hide StringBuffer;
import 'package:at_client/src/encryption_service/encryption.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/notification_response_parser.dart';
import 'package:at_client/src/response/response.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:at_client/src/transformer/response_transformer/notification_response_transformer.dart';
import 'package:at_client/src/util/at_client_validation.dart';
import 'package:at_client/src/util/regex_match_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart'
    as at_persistence_secondary_server;
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart' show Uuid;

class NotificationServiceImpl extends NotificationService {
  final Map<NotificationConfig, StreamController> _streamListeners =
      HashMap(equals: _compareNotificationConfig, hashCode: _generateHashCode);
  final emptyRegex = '';
  static const notificationIdKey = '_latestNotificationIdv2';

  /// [lastReceivedNotificationKey] has been converted to lowercase
  /// from at_client v3.0.59
  static const lastReceivedNotificationKey = 'lastreceivednotification';

  final AtClient atClient;
  late final Monitor monitor;
  late final AtSignLogger logger;
  DateTime? _lastReceipt;

  @visibleForTesting
  late AtKeyEncryptionManager atKeyEncryptionManager;

  @visibleForTesting
  AtClientValidation atClientValidation = AtClientValidation();

  @visibleForTesting
  late AtKey lastReceivedNotificationAtKey;

  @override
  Atsign get atSign => atClient.atSign;

  late SecondaryAddressFinder secondaryAddressFinder;

  /// - [monitor] is providable for unit test purposes
  static Future<NotificationService> create(AtClient atClient,
      {@Deprecated('will be removed in a future version')
      AtClientManager? atClientManager,
      Monitor? monitor,
      SecondaryAddressFinder? secondaryAddressFinder}) async {
    return NotificationServiceImpl._(
        atClient: atClient,
        monitor: monitor,
        secondaryAddressFinder: secondaryAddressFinder);
  }

  NotificationServiceImpl._(
      {required this.atClient,
      Monitor? monitor,
      SecondaryAddressFinder? secondaryAddressFinder}) {
    logger = AtSignLogger(
        'NotificationServiceImpl (${atClient.getCurrentAtSign()})');

    this.secondaryAddressFinder = secondaryAddressFinder ??
        CacheableSecondaryAddressFinder(atClient.getPreferences()!.rootDomain,
            atClient.getPreferences()!.rootPort);

    this.monitor = monitor ??
        Monitor(
          atSign: atSign,
          atClientPreference: atClient.getPreferences()!,
          atChops: atClient.atChops,
          enrollmentId: atClient.enrollmentId,
          handleNotification: handleNotificationReceipt,
          getLastNotificationTime: getLastNotificationTime,
          secondaryAddressFinder: this.secondaryAddressFinder,
        );

    lastReceivedNotificationAtKey = AtKey.local(
            lastReceivedNotificationKey, atClient.getCurrentAtSign()!,
            namespace: atClient.getPreferences()!.namespace)
        .build();
    atKeyEncryptionManager = AtKeyEncryptionManager(atClient);
  }

  /// Return the last received notification DateTime in epochMillis when
  /// [AtClientPreference.fetchOfflineNotifications] is set true.
  ///
  /// Returns null when the key which holds the lastNotificationReceived
  /// does not exist.
  @visibleForTesting
  Future<int?> getLastNotificationTime() async {
    if (atClient.getPreferences()!.fetchOfflineNotifications == false) {
      // fetchOfflineNotifications == false means issue `monitor` command without a lastNotificationTime
      // which will result in the server not sending any previously received notifications
      return null;
    }

    // fetchOfflineNotifications == true (the default) means we want all notifications since the last one we received
    // We keep track of the last notification id in the client-side key store
    // Check if the new key (local:lastNotificationReceived@alice) is available in the keystore.
    // If yes, fetch the value;
    AtValue? atValue;
    if (atClient
        .getLocalSecondary()!
        .keyStore!
        .isKeyExists(lastReceivedNotificationAtKey.toString())) {
      atValue = await atClient.get(lastReceivedNotificationAtKey);
    }
    // If new key does not exist or value is null, check for the old key (_latestNotificationIdv2@alice)
    // If old key exist, fetch the value and update the new key with old key's value
    if (atValue == null || atValue.value == null) {
      var lastNotificationKeyStr =
          '$notificationIdKey.${atClient.getPreferences()!.namespace}${atClient.getCurrentAtSign()}';
      var atKey = AtKey.fromString(lastNotificationKeyStr);
      if (atClient
          .getLocalSecondary()!
          .keyStore!
          .isKeyExists(lastNotificationKeyStr)) {
        try {
          atValue = await atClient.get(atKey);
          await atClient.put(lastReceivedNotificationAtKey, atValue.value);
        } on Exception catch (e) {
          logger.severe(
              'Exception in getting last notification id: ${e.toString}');
        }
      }
    }
    if (atValue?.value != null) {
      logger.finer('json from hive: ${atValue?.value}');
      return jsonDecode(atValue?.value)['epochMillis'];
    }

    // If we're here, we've never received a notification, since the last
    // notification received time has never been saved.
    //
    // In that case, we're going to set the last notification received time to
    // _now_
    //
    // But we're still going to return null. But then, next time we're called,
    // we'll have a value to return.
    //
    // This upholds the principle of least surprise which is that
    // - I run a client for the first time, I get no notifications from the past
    // - But let's assume you only run the client for a very short period, so
    //   you get no notifications before you shut it down.
    // - You run up the client again some time later, assuming that any
    //   notifications received while you were offline will be delivered to you
    // - And now because we did this last time, that will be true. Whereas
    //   previously, you would simply have got no notifications, again.
    AtNotification n = AtNotification(
      'abcd-123456-wxyz',
      '@bob:notification.foo.bar.baz@alice',
      '@alice',
      '@bob',
      DateTime.now().millisecondsSinceEpoch,
      MessageTypeEnum.key.toString(),
      false,
      value: 'placeholder',
      metadata: Metadata(),
    );
    await atClient.put(lastReceivedNotificationAtKey, jsonEncode(n.toJson()));

    return null;
  }

  @visibleForTesting
  bool isStopped = false;

  Future<void> stop() async {
    stopAllSubscriptions();
  }

  @override
  void stopAllSubscriptions({bool stopNotificationsListener = true}) {
    if (isStopped) {
      logger.info(
          'stopAllSubscriptions() called, but service is already stopped. Ignoring.');
      return;
    }
    isStopped = true;

    if (stopNotificationsListener) {
      stopListening();
    }

    _streamListeners.forEach((regex, streamController) {
      if (!streamController.isClosed) {
        streamController.close();
      }
    });
    _streamListeners.clear();
  }

  final notificationParser = NotificationResponseParser();

  @visibleForTesting
  Future<void> handleNotificationReceipt(String notificationJSON) async {
    try {
      logger.finest('DEBUG: $notificationJSON');
      if (isStopped) return;

      final notifs = notificationParser
          .getAtNotifications(notificationParser.parse(notificationJSON));
      _lastReceipt = DateTime.now().toUtc();
      for (var notif in notifs) {
        logger.info('Received ${notif.key}');
        // Saves latest notification id to the keys if its not a stats notification.
        if (notif.id != '-1') {
          try {
            await atClient.put(
                lastReceivedNotificationAtKey, jsonEncode(notif.toJson()));
          } catch (e) {
            logger.warning('Failed to save last received notification ID: $e');
          }
        }
        _streamListeners.forEach((notificationConfig, streamController) async {
          try {
            var transformedNotification =
                await NotificationResponseTransformer(atClient)
                    .transform(Tuple()
                      ..one = notif
                      ..two = notificationConfig);

            if (notificationConfig.regex != emptyRegex) {
              if (hasRegexMatch(notif.key, notificationConfig.regex)) {
                streamController.add(transformedNotification);
              }
            } else {
              streamController.add(transformedNotification);
            }
          } catch (e) {
            logger.finer('Caught $e while dispatching to to subscribers');
          }
        });
      }
    } catch (e) {
      logger.severe('unexpected error:${e.toString()}'
          ' while processing notificationJson: $notificationJSON');
    }
  }

  @override
  Future<String> send({
    required Atsign to,
    required String namespace,
    String body = '',
    bool shouldEncrypt = true,
    Duration expiration = NotificationService.defaultExpiration,
    bool cacheAtRecipient = false,
    DateTime? recipientCacheExpiration,
  }) async {
    if (cacheAtRecipient && recipientCacheExpiration == null) {
      throw ArgumentError(
          'You must supply recipientCacheExpiration when cacheAtRecipient is true');
    }
    final String key = '$to:$namespace$atSign';
    final AtKey atKey = AtKey.fromString(key);
    atKey.metadata.namespaceAware = false;
    final String notifPayload;
    body = body.trim();
    if (body.isNotEmpty && shouldEncrypt) {
      AtKeyEncryption encrypter = atSign == to
          ? SelfKeyEncryption(atClient)
          : SharedKeyEncryption(atClient);
      notifPayload = await encrypter.encrypt(atKey, body);
      atKey.metadata.isEncrypted = true;
    } else {
      notifPayload = body;
      atKey.metadata.isEncrypted = false;
    }

    if (cacheAtRecipient) {
      atKey.metadata.ttr = -1;
      int ttl = recipientCacheExpiration!.millisecondsSinceEpoch -
          DateTime.now().millisecondsSinceEpoch;
      if (ttl < 0) {
        ttl = 1;
      }
      atKey.metadata.ttl = ttl;
    }

    final String id = Uuid().v4();
    StringBuffer sb = StringBuffer();
    sb.write('notify:id:$id');
    sb.write(':ttln:${expiration.inMilliseconds}');
    sb.write(atKey.metadata.toAtProtocolFragment());
    sb.write(':$key');

    if (notifPayload.isNotEmpty) {
      sb.write(':$notifPayload');
    }

    sb.write('\n');

    logger.info('SENDING: $key');

    await atClient
        .getRemoteSecondary()
        ?.executeCommand(sb.toString(), auth: true);

    return id;
  }

  @override
  Stream<AtNotification> subscribeFiltered({
    Set<Atsign>? acceptedSenders,
    required String namespace,
  }) {
    String r = '^$atSign:([^.]+\\.)?$namespace@';
    StreamController<AtNotification> sc = StreamController<AtNotification>();
    StreamSubscription<AtNotification>? notifStreamSubscription;
    sc.onListen = () {
      Stream<AtNotification> notifStream = subscribe(
        regex: r,
        shouldDecrypt: true,
      );
      notifStreamSubscription = notifStream.listen((AtNotification n) async {
        if (acceptedSenders == null || acceptedSenders.contains(n.from)) {
          sc.add(n);
        } else {
          logger.warning('Ignored notification ${n.key}');
        }
      });
    };
    sc.onCancel = () {
      notifStreamSubscription?.cancel();
    };
    sc.onPause = () {
      notifStreamSubscription?.pause();
    };
    sc.onResume = () {
      notifStreamSubscription?.resume();
    };
    return sc.stream;
  }

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {bool waitForFinalDeliveryStatus =
          true, // this was the behaviour before introducing this parameter
      bool checkForFinalDeliveryStatus =
          true, // this was the behaviour before introducing this parameter
      bool encryptValue =
          true, // this was the behaviour before introducing this parameter
      Function(NotificationResult)? onSuccess,
      Function(NotificationResult)? onError,
      Function(NotificationResult)? onSentToSecondary}) async {
    var notificationResult = NotificationResult()
      ..notificationID = notificationParams.id
      ..atKey = notificationParams.atKey;

    notificationParams.atKey.metadata.ivNonce ??= EncryptionUtil.generateIV();

    try {
      notificationParams.atKey.metadata.isEncrypted = encryptValue;
      // If sharedBy atSign is null, default to current atSign.
      if (notificationParams.atKey.sharedBy.isNull) {
        notificationParams.atKey.sharedBy = atClient.getCurrentAtSign();
      }
      // Prepend '@' if not already set.
      notificationParams.atKey.sharedBy =
          AtUtils.fixAtSign(notificationParams.atKey.sharedBy!);
      // validate notification request
      await atClientValidation.validateNotificationRequest(
          secondaryAddressFinder,
          notificationParams,
          atClient.getPreferences()!,
          atClient.getCurrentAtSign()!);
      // Get the EncryptionInstance to encrypt the data.
      var atKeyEncryption = atKeyEncryptionManager.get(
          notificationParams.atKey, atClient.getCurrentAtSign()!);
      // Get the NotifyVerbBuilder from NotificationParams
      var builder = await NotificationRequestTransformer(
              atClient.getCurrentAtSign()!,
              atClient.getPreferences()!,
              atKeyEncryption)
          .transform(notificationParams);

      notificationValueValidation(notificationParams, builder);
      // Run the notify verb on the remote secondary instance.
      await atClient.getRemoteSecondary()?.executeVerb(builder);
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

  /// Checks the size the notification value. If the size exceeds the [AtClientPreference.maxDataSize]
  /// [BufferOverFlowException] is thrown.
  ///
  @visibleForTesting
  void notificationValueValidation(
      NotificationParams notificationParams, NotifyVerbBuilder builder) {
    // ignore: deprecated_member_use_from_same_package
    switch (notificationParams.messageType) {
      case MessageTypeEnum.key:
        // Since value is not mandatory in AtNotification, perform validation only if
        // value is not null.
        if (builder.value != null &&
            builder.value.length > atClient.getPreferences()!.maxDataSize) {
          throw BufferOverFlowException(
              'The length of value exceeds the maximum allowed length. Maximum buffer size is ${atClient.getPreferences()!.maxDataSize} bytes. Found ${builder.value.toString().length} bytes');
        }
        break;

      // ignore: deprecated_member_use
      case MessageTypeEnum.text:
        // When messageType is text, the "text" to notify is added to the key. Hence validating
        // the key length
        if (builder.atKey.key.length > atClient.getPreferences()!.maxDataSize) {
          throw BufferOverFlowException(
              'The length of value exceeds the maximum allowed length. Maximum buffer size is ${atClient.getPreferences()!.maxDataSize} bytes. Found ${builder.value.toString().length} bytes');
        }
        break;
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
      status = await atClient.notifyStatus(notificationId);
    }
    return status;
  }

  @visibleForTesting
  Timer? delayedStartListeningTimer;

  @visibleForTesting
  Duration? delayedStartListeningTimerDuration;

  @override
  Stream<AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    logger.finer('subscribe(regex: $regex, shouldDecrypt: $shouldDecrypt');
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
    //
    // Additionally, in order to give application code full control over the
    // lifecycle of the notifications listener, we will only start the monitor
    // for subscriptions when AtClientPreference.autoStartMonitor] is true,
    // which it is by default (legacy behaviour). This gives application code
    // much better clear control over the notification listening lifecycle.
    if (atClient.getPreferences()?.monitorAutoStart == true) {
      if (regex == 'statsNotification') {
        delayedStartListeningTimerDuration ??= Duration(seconds: 30);
        delayedStartListeningTimer =
            Timer(delayedStartListeningTimerDuration!, startListening);
      } else {
        startListening();
      }
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
  Future<NotificationResult> getStatus(String notificationId) async {
    var status = await atClient.notifyStatus(notificationId);
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
  int getStreamListenersCount() {
    return _streamListeners.length;
  }

  @override
  Future<AtNotification> fetch(String notificationId) async {
    var notifyFetchVerbBuilder = NotifyFetchVerbBuilder()
      ..notificationId = notificationId;
    String? atNotificationStr;
    try {
      atNotificationStr = await atClient
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
      ..messageType = atNotificationMap['messageType']
      ..expiresAtInEpochMillis =
          DateTime.parse(atNotificationMap['expiresAt']).millisecondsSinceEpoch;
  }

  @override
  void startListening() {
    if (monitor.targetState == NotificationListenerState.listening) {
      logger.info('startListening() called, but already targeting listening');
      return;
    }
    logger.info('startListening(): starting notification listener');
    monitor.start();
  }

  @override
  void stopListening() {
    if (delayedStartListeningTimer != null) {
      delayedStartListeningTimer!.cancel();
      delayedStartListeningTimer = null;
    }
    if (monitor.targetState == NotificationListenerState.notConnected) {
      logger.info('stopListening() called, but'
          ' target state is already ${monitor.targetState}');
      return;
    }

    logger.info('stopListening() called: stopping notification listener');
    monitor.stop();
  }

  @override
  NotificationListenerState get currentListenerState => monitor.currentState;

  @override
  NotificationListenerState get targetListenerState => monitor.targetState;

  @override
  DateTime? get lastReceipt => _lastReceipt;

  @override
  Stream<NotificationListenerState> get currentListenerStateStream =>
      monitor.currentStateStream;
}
