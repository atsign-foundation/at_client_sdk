import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart' hide StringBuffer;
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

  final String myStatsNotifKey;

  NotificationServiceImpl._(
      {required this.atClient,
      Monitor? monitor,
      SecondaryAddressFinder? secondaryAddressFinder})
      : myStatsNotifKey = 'statsNotification.${atClient.atSign}' {
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
          signingAlgoType: atClient.signingAlgoType,
          handleNotification: handleNotificationReceipt,
          getLastNotificationTime: getLastNotificationTime,
          secondaryAddressFinder: this.secondaryAddressFinder,
        );

    lastReceivedNotificationAtKey = AtKey.local(
            lastReceivedNotificationKey, atClient.getCurrentAtSign()!,
            namespace: atClient.getPreferences()!.namespace)
        .build();
  }

  /// Migrate any legacy (non-`local:`) forms of the
  /// last-received-notification key to the canonical
  /// `local:lastreceivednotification.<ns>@<atSign>` form, and delete
  /// every legacy form found so they no longer pollute the local
  /// keystore.
  ///
  /// Fixes the underlying defect behind #1942 — `AtCollection`
  /// regex scans over the local keystore were matching the bare
  /// (non-`local:`) `lastreceivednotification.<ns>@<atSign>` key
  /// because it has the same structural shape as a self-owned
  /// collection item. The canonical key has been `local:`-prefixed
  /// since the move to `AtKey.local`, but clients upgraded from
  /// older builds still carry the bare form on disk.
  ///
  /// Three forms have existed:
  ///   1. `local:lastreceivednotification.<ns>@<atSign>` — canonical
  ///   2. `      lastreceivednotification.<ns>@<atSign>` — intermediate
  ///   3. `      _latestNotificationIdv2.<ns>@<atSign>`  — original
  ///
  /// If the canonical key is missing its value is seeded from the
  /// newest legacy form that has one (preferring the intermediate
  /// over the original — its value is fresher). Every legacy entry
  /// is then deleted. The migration is idempotent: re-running it
  /// after a clean DB is a no-op.
  ///
  /// Deletes are local-only — both legacy name prefixes are
  /// excluded by `SyncUtil.shouldSync`, so the removals do not
  /// propagate to the atServer.
  /// Returns the canonical value after migration. The seeded value
  /// is returned directly (rather than re-read by the caller) so the
  /// `put` we just did doesn't have to round-trip back through a
  /// `get` — useful both for performance and because some mocks /
  /// fakes aren't stateful across the put-then-get.
  @visibleForTesting
  Future<AtValue?> migrateLegacyLastReceivedNotificationKeysForTest() =>
      _migrateLegacyLastReceivedNotificationKeys();

  Future<AtValue?> _migrateLegacyLastReceivedNotificationKeys() async {
    final keyStore = atClient.getLocalSecondary()!.keyStore!;
    final ns = atClient.getPreferences()!.namespace;
    final currentAtSign = atClient.getCurrentAtSign()!;
    final canonicalStr = lastReceivedNotificationAtKey.toString();

    // The canonical key can exist with a null value (e.g. when an
    // earlier `put` seeded a placeholder). Check the actual value,
    // not just existence — otherwise we'd never seed from a legacy
    // form when the canonical row is present-but-empty.
    AtValue? canonicalValue;
    if (await keyStore.exists(canonicalStr)) {
      try {
        canonicalValue = await atClient.get(lastReceivedNotificationAtKey);
        if (canonicalValue.value == null) canonicalValue = null;
      } on Exception {
        // Treat read failures as "needs seeding" — the legacy
        // forms become the source of truth.
      }
    }

    // Newest legacy form first so we prefer fresher values when
    // seeding the canonical key.
    final legacyForms = <String>[
      'lastreceivednotification.$ns$currentAtSign',
      '$notificationIdKey.$ns$currentAtSign',
    ];
    for (final legacyStr in legacyForms) {
      if (!await keyStore.exists(legacyStr)) continue;

      // Seed the canonical key from the first legacy form that has a
      // value — only when the canonical doesn't already carry one.
      if (canonicalValue == null) {
        try {
          final v = await atClient.get(AtKey.fromString(legacyStr));
          if (v.value != null) {
            await atClient.put(lastReceivedNotificationAtKey, v.value);
            canonicalValue = v;
          }
        } on Exception catch (e) {
          logger.warning(
              'Migration: failed to seed canonical key from $legacyStr: $e');
        }
      }

      // Drop the legacy key regardless of whether we seeded from it
      // — older forms are no longer load-bearing once the canonical
      // exists, and pollute the local keystore (#1942).
      try {
        await atClient.delete(AtKey.fromString(legacyStr));
      } on Exception catch (e) {
        logger.warning('Migration: failed to delete legacy key $legacyStr: $e');
      }
    }
    return canonicalValue;
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

    // Migration runs first and returns the canonical key's value
    // (either the pre-existing value or one freshly seeded from a
    // legacy form). Use that directly instead of re-reading the
    // canonical key — the migration has already done that work.
    AtValue? atValue = await _migrateLegacyLastReceivedNotificationKeys();
    if (atValue?.value != null) {
      logger.finer('json from hive: ${atValue?.value}');
      return jsonDecode(atValue?.value)['epochMillis'];
    }

    // First-call branch: no last-received-notification record exists.
    // Set the record to "now" so that subsequent calls (after a
    // restart, say) will return a value, but return null for THIS
    // call to keep first-run semantics ("don't replay history I never
    // saw"). Without this seed, a short-lived first session followed
    // by a longer second session would silently miss any notifications
    // that arrived in between.
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
      for (var n in notifs) {
        if (n.key == myStatsNotifKey) {
          logger.finer('Received ${n.key} (serverCommitId) ${n.value}');
        } else {
          logger.info('Received ${n.key}');
        }
        // Saves latest notification id to the keys if its not a stats notification.
        if (n.id != '-1') {
          try {
            await atClient.put(
                lastReceivedNotificationAtKey, jsonEncode(n.toJson()));
          } catch (e) {
            logger.warning('Failed to save last received notification ID: $e');
          }
        }
        _streamListeners.forEach((notificationConfig, streamController) async {
          try {
            var transformedNotification =
                await NotificationResponseTransformer(atClient)
                    .transform(Tuple()
                      ..one = n
                      ..two = notificationConfig);

            if (notificationConfig.regex != emptyRegex) {
              if (hasRegexMatch(n.key, notificationConfig.regex)) {
                streamController.add(transformedNotification);
              }
            } else {
              streamController.add(transformedNotification);
            }
          } catch (e) {
            // Warning, not finer. A notification that cannot be transformed is
            // dropped here and never retried — nothing re-delivers it when the
            // missing piece arrives. At finer the subscriber saw an absence
            // indistinguishable from one that was never sent, which is how a
            // conveyance racing its own announcement stayed invisible through
            // a green unit suite and a green e2e suite alike.
            logger.warning('Dropping notification ${n.key} for subscriber '
                '(regex "${notificationConfig.regex}"): $e');
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
    String? cryptoProviderId,
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
      // Resolve through the runtime so a provider that cannot serve this key —
      // the nskey path declines anything without a namespace — is not selected
      // for it, and so the same preparation step runs as on any other write.
      final providerId =
          CryptoRuntime.providerIdFor(atClient, cryptoProviderId, atKey: atKey);
      atKey.metadata.appMetadata ??= AppMetadata(providerId: providerId);
      // Remote, unconditionally: a notification is remote-only by construction,
      // so a conveyance left to reach the atServer by sync is announced before
      // it exists and the recipient resolves the key inline with nothing there.
      await CryptoRuntime(atClient)
          .prepareForPut(atKey, providerId, useRemoteAtServer: true);
      notifPayload =
          await CryptoRuntime(atClient).encryptForNotification(atKey, body);
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
    // Single-subscription controller. Its onPause/onResume hooks are
    // deliberately NOT wired to pause the upstream subscription:
    // [subscribe] returns a broadcast stream, and broadcast
    // subscriptions DO NOT buffer events emitted during pause()
    // (events are delivered to other live subscribers and dropped
    // for the paused one). When the downstream consumer pauses
    // [sc.stream], the single-sub controller buffers incoming
    // notifications internally; we keep accepting from upstream
    // and adding to the controller, and the controller delivers
    // the buffered notifications when the consumer resumes.
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
    return sc.stream;
  }

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {bool waitForFinalDeliveryStatus = true,
      bool checkForFinalDeliveryStatus = true,
      bool encryptValue = true,
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
      // Get the NotifyVerbBuilder from NotificationParams
      var builder = await NotificationRequestTransformer(atClient)
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
    // for subscriptions when AtClientPreference.monitorAutoStart is true,
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
