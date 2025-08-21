import 'dart:async';
import 'dart:convert' show jsonEncode, jsonDecode;

import 'package:at_client/at_client.dart'
    show AtClient, AtNotification, NotificationResult;
import 'package:at_client/at_client_mixins.dart' show AtClientBindings;
import 'package:at_commons/at_commons.dart' show AtKey, Metadata, AtsignString;
import 'package:at_utils/at_utils.dart' show AtSignLogger;
import 'package:meta/meta.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:uuid/v4.dart' show UuidV4;

const uuid = UuidV4();

class AtNotificationStreamChannel<Value, Encoded>
    with AtClientBindings, StreamChannelMixin<Value>
    implements StreamChannel<Value> {
  @override
  final AtSignLogger logger = AtSignLogger("AtStreamChannel");

  // Inputs
  @override
  final AtClient atClient;
  final String otherAtsign;
  final String baseNamespace;
  final String domainNamespace;
  final Duration sessionTimeout;
  final StreamTransformer<(AtNotification, Encoded), Value> recvTransformer;
  final StreamTransformer<Value, Encoded> sendTransformer;

  // State
  late final String sessionId;
  Timer? timer;
  int _messageCounter = 0;
  final StreamController<Value> _sendController = StreamController<Value>();
  final StreamController<Value> _recvController = StreamController<Value>();

  // Lifecycle state
  bool _initStarted = false;
  final Completer _initCompleter = Completer();
  Future get initialized => _initCompleter.future;
  Future get done => Future.wait([_sendController.done, _recvController.done]);

  // Getters
  @override
  StreamSink<Value> get sink => _sendController.sink;
  @override
  Stream<Value> get stream => _recvController.stream;

  /// If you use this constructor, you must call [initServer] or [initClient]
  /// yourself.
  AtNotificationStreamChannel(
    this.atClient, {
    required this.otherAtsign,
    required this.baseNamespace,
    required this.domainNamespace,
    required this.recvTransformer,
    required this.sendTransformer,
    this.sessionTimeout = const Duration(minutes: 30),
    String? sessionId,
  }) : sessionId = sessionId ?? uuid.generate();

  /// Connect to an [AtNotificationStreamChannel] which has a running [bind] listener
  static FutureOr<AtNotificationStreamChannel<Value, Encoded>>
      connect<Value, Encoded>(
    AtClient atClient, {
    required String otherAtsign,
    required String baseNamespace,
    required String domainNamespace,
    required StreamTransformer<(AtNotification, Encoded), Value>
        recvTransformer,
    required StreamTransformer<Value, Encoded> sendTransformer,
    Duration handshakeTimeout = const Duration(seconds: 5),
  }) async {
    var channel = AtNotificationStreamChannel<Value, Encoded>(
      atClient,
      otherAtsign: otherAtsign,
      baseNamespace: baseNamespace,
      domainNamespace: domainNamespace,
      recvTransformer: recvTransformer,
      sendTransformer: sendTransformer,
    );
    await channel.initClient(handshakeTimeout: handshakeTimeout);
    return channel;
  }

  /// Helper function if you want to create your own implementation of [bind]
  /// This is the stream of messages to listen for connect messages on
  static Stream<AtNotification> createConnectionRequestListener(
    AtClient atClient, {
    required String baseNamespace,
    required String domainNamespace,
  }) {
    return atClient.notificationService.subscribe(
      regex: "connect\\.$domainNamespace\\.$baseNamespace@",
      shouldDecrypt: true,
    );
  }

  /// Bind a listener for new AtStreamChannel connection requests
  /// and provides the resulting AtStreamChannel here
  static Stream<AtNotificationStreamChannel<Value, Encoded>>
      bind<Value, Encoded>(
    AtClient atClient, {
    required String baseNamespace,
    required String domainNamespace,
    required StreamTransformer<(AtNotification, Encoded), Value>
        recvTransformer,
    required StreamTransformer<Value, Encoded> sendTransformer,
    Duration sessionTimeout = const Duration(seconds: 10),
    AtSignLogger? logger,
  }) {
    final controller =
        StreamController<AtNotificationStreamChannel<Value, Encoded>>();
    createConnectionRequestListener(
      atClient,
      baseNamespace: baseNamespace,
      domainNamespace: domainNamespace,
    ).listen((AtNotification notification) async {
      logger?.finer("Got notification: $notification");
      final sessionId = notification.value;
      final otherAtsign = notification.from.toAtsign();

      final channel = AtNotificationStreamChannel(
        // General
        atClient,
        baseNamespace: baseNamespace,
        domainNamespace: domainNamespace,
        recvTransformer: recvTransformer,
        sendTransformer: sendTransformer,
        // Session based
        otherAtsign: otherAtsign,
        sessionId: sessionId,
      );
      try {
        await channel.initServer();
      } catch (e) {
        logger?.severe(
          "Failed to initialize AtStreamChannel server session: $e",
        );
        return;
      }
      controller.add(channel);
    });

    return controller.stream;
  }

  /// Use this to initialize a server session
  Future<void> initServer() async {
    if (_initStarted) return initialized;
    _initStarted = true;
    await initBase(onDone: sendDisconnectMessage);

    AtKey key = AtKey()
      ..key = "${_messageCounter++}.$sessionId"
      ..namespace = "$domainNamespace.$baseNamespace"
      ..sharedWith = otherAtsign
      ..sharedBy = atClient.getCurrentAtSign()!
      ..metadata = (Metadata()
        ..isEncrypted = true
        ..namespaceAware = false);
    await notify(
      key,
      jsonEncode({"control": "connected"}),
      checkForFinalDeliveryStatus: true,
      waitForFinalDeliveryStatus: false,
      ttln: Duration(minutes: 5),
    );
    _initCompleter.complete();
  }

  /// Use this to initialize a client session
  Future<void> initClient({required Duration handshakeTimeout}) async {
    if (_initStarted) return initialized;
    _initStarted = true;
    await initBase(onDone: sendDisconnectMessage);

    AtKey key = AtKey()
      ..key = "connect"
      ..namespace = "$domainNamespace.$baseNamespace"
      ..sharedWith = otherAtsign
      ..sharedBy = atClient.getCurrentAtSign()!
      ..metadata = (Metadata()
        ..isEncrypted = true
        ..namespaceAware = false);
    await notify(
      key,
      sessionId,
      checkForFinalDeliveryStatus: true,
      waitForFinalDeliveryStatus: false,
      ttln: Duration(minutes: 5),
    );
    return _initCompleter.future.timeout(
      handshakeTimeout,
      onTimeout: () {
        throw TimeoutException("AtStreamChannel handshake timed out.");
      },
    );
  }

  /// If you've built a custom [AtNotificationStreamChannel], use this to tell the far
  /// side that you are disconnecting and it can too.
  Future<NotificationResult> sendDisconnectMessage() {
    AtKey key = AtKey()
      ..key = "${_messageCounter++}.$sessionId"
      ..namespace = "$domainNamespace.$baseNamespace"
      ..sharedWith = otherAtsign
      ..sharedBy = atClient.getCurrentAtSign()!
      ..metadata = (Metadata()
        ..isEncrypted = true
        ..namespaceAware = false);
    return notify(
      key,
      jsonEncode({"control": "disconnect"}),
      checkForFinalDeliveryStatus: true,
      waitForFinalDeliveryStatus: false,
      ttln: const Duration(hours: 1),
    );
  }

  Future close() {
    // Even though sendDisconnectMessage is already called inside the
    // sendController.listen's onDone, the onDone function isn't
    // called before close completes, thus we potentially run it twice
    // If a client calls close then exits, then notification is never sent.
    // Thus, we send disconnect first to ensure that the notification stream
    // is closed and free up the other side's resources sooner.
    timer?.cancel();
    return sendDisconnectMessage().then((_) => _sendController.close());
  }

  void onTimeout() {
    logger.shout("Session $sessionId timed out.");
    close();
  }

  void resetTimer() {
    timer?.cancel();
    timer = Timer(sessionTimeout, onTimeout);
  }

  @protected
  @visibleForTesting
  Future<void> initBase({FutureOr<void> Function()? onDone}) async {
    timer = Timer(sessionTimeout, onTimeout);
    // sending
    _sendController.stream.transform(sendTransformer).listen(
      (Encoded value) async {
        resetTimer();
        logger.info("Sending message: $value");

        AtKey key = AtKey()
          ..key = "${_messageCounter++}.$sessionId"
          ..namespace = "$domainNamespace.$baseNamespace"
          ..sharedWith = otherAtsign
          ..sharedBy = atClient.getCurrentAtSign()!
          ..metadata = (Metadata()
            ..isEncrypted = true
            ..namespaceAware = false);
        try {
          final data = {'payload': value};
          await notify(
            key,
            jsonEncode(data),
            checkForFinalDeliveryStatus: true,
            waitForFinalDeliveryStatus: false,
            ttln: const Duration(hours: 1),
          );
        } catch (e) {
          logger.severe("Failed to send message: $e");
        }
      },
      onDone: () async {
        await onDone?.call();
        await _recvController.close();
      },
    );

    // receiving
    subscribe(
      regex: "$sessionId\\.$domainNamespace\\.$baseNamespace$otherAtsign",
      shouldDecrypt: true,
    )
        .transform(StreamTransformer<AtNotification,
            (AtNotification, Encoded)>.fromHandlers(
          handleData: (notification, sink) async {
            resetTimer();
            logger.info("Got notification: $notification");
            if (notification.value == null) return;
            try {
              final data = jsonDecode(notification.value!);
              if (data == null || data is! Map) {
                logger.warning(
                  "Received invalid data from notification:"
                  " $data",
                );
                return;
              }
              if (data.containsKey("control")) {
                logger.info("Received control message: ${data["control"]}");
                switch (data["control"]) {
                  case "connected":
                    logger.info(
                      "Connected message from: ${notification.from}"
                      " session: $sessionId",
                    );
                    if (_initCompleter.isCompleted) return;
                    _initCompleter.complete();
                    return;
                  case "disconnect":
                    logger.info(
                      "Disconnect message from: ${notification.from}"
                      " session: $sessionId",
                    );
                    unawaited(_sendController.close());
                    return;
                }
              }
              if (!data.containsKey("payload")) {
                logger.warning(
                  "Missing payload from notification:"
                  " $data",
                );
              }
              sink.add((notification, data["payload"]));
            } catch (e) {
              logger.severe("Error decoding message: $e");
            }
          },
        ))
        .transform(recvTransformer)
        .listen((value) => _recvController.add(value));
  }
}
