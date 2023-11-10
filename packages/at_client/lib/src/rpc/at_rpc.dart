import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_utils.dart';
import 'package:meta/meta.dart';

/// The callbacks which the creator of the [AtRpc] object needs to provide
abstract class AtRpcCallbacks {
  /// Called when a 'request' is received
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign);

  /// Called when a 'response' is received
  Future<void> handleResponse(AtRpcResp response);
}

@experimental
class AtRpcClient implements AtRpcCallbacks {
  static final AtSignLogger logger = AtSignLogger(' AtRpcClient ', loggingHandler: AtSignLogger.stdErrLoggingHandler);

  late final String serverAtsign;
  late final AtRpc rpc;

  Map<int, Completer<Map<String, dynamic>>> completerMap = {};

  AtRpcClient({
    required String serverAtsign,
    required AtClient atClient,
    required String baseNameSpace, // e.g. my_app
    String rpcsNameSpace = '__rpcs',
    required String domainNameSpace, // e.g. math_evaluator
  }) {
    this.serverAtsign = AtUtils.fixAtSign(serverAtsign);
    rpc = AtRpc(
      atClient: atClient,
      baseNameSpace: baseNameSpace,
      rpcsNameSpace: rpcsNameSpace,
      domainNameSpace: domainNameSpace,
      callbacks: this,
      allowList: {},
    );
    rpc.start();
  }

  Future<Map<String, dynamic>> call (Map<String, dynamic> payload) async {
    AtRpcReq request = AtRpcReq.create(payload);
    completerMap[request.reqId] = Completer();
    logger.info('Sending request to $serverAtsign : $request');
    await rpc.sendRequest(toAtSign: serverAtsign, request: request);
    return completerMap[request.reqId]!.future;
  }

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) {
    // We're just a client, we don't handle requests
    throw UnimplementedError();
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async {
    logger.info('Got response ${response.payload}');

    final Completer? completer = completerMap[response.reqId];

    if (completer == null || completer.isCompleted) {
      logger.warning(
          'Ignoring response, no completer found : $response');
      return;
    }

    switch (response.respType) {
      case AtRpcRespType.ack:
      // We don't complete the future when we get an ack
        logger.info(
            'Got ack : $response');
        break;
      case AtRpcRespType.success:
        logger.info(
            'Got auth check response : $response');
        completer.complete(response.payload);
        completerMap.remove(response.reqId);
        break;
      default:
        logger.warning(
            'Got non-success response '
                ' : $response');
        completer.completeError('Got non-success response : $response');
        completerMap.remove(response.reqId);
        break;
    }
  }
}

/// A simple rpc request-response abstraction which uses atProtocol
/// notifications under the hood.
/// - 'requests' are sent as notifications with a 'key' like:
/// request.&lt;requestId&gt;.[domainNameSpace].[rpcsNameSpace].[baseNameSpace]
/// - 'responses' are sent as notifications with a 'key' like:
/// &lt;ack|nack|success|error&gt;.&lt;requestId&gt;.[domainNameSpace].[rpcsNameSpace].[baseNameSpace]
///
/// Sample usage:
/// - Requester:
/// ```
/// ```
/// - Responder:
/// ```
/// ```
@experimental
class AtRpc {
  static final AtSignLogger logger = AtSignLogger('AtRpc');

  static Duration defaultNotificationExpiry = Duration(seconds: 30);

  /// The [AtClient] used by this AtRpc
  final AtClient atClient;

  /// Base namespace, typically the namespace used by the using application.
  /// For example an app called 'Buzz' could have a namespace like `'buzz'` or
  /// `'buzz_app'`
  final String baseNameSpace;

  /// A namespace within the [baseNameSpace] which should be used just for RPCs.
  /// Defaults to `'__rpcs'`
  final String rpcsNameSpace;

  /// A namespace within the [rpcsNameSpace], allowing logical separation of
  /// different types of RPCs. Apps can then create multiple AtRpc objects,
  /// each of which is sending and / or listening to a subset of the RPCs.
  final String domainNameSpace;

  /// The list of atSigns you wish to be able to send requests to you. Any
  /// requests received from any atSign not in this list will be discarded
  /// and not delivered to the [AtRpcCallbacks.handleRequest] callback
  final Set<String> allowList;

  /// The callback functions which will be called when requests or responses
  /// are received
  final AtRpcCallbacks callbacks;

  /// The stream of request notifications
  Stream<AtNotification>? _requestStream;

  /// The stream of request notifications
  Stream<AtNotification>? get requestStream => _requestStream;

  /// The stream of response notifications
  Stream<AtNotification>? _responseStream;

  /// The stream of response notifications
  Stream<AtNotification>? get responseStream => _responseStream;

  /// When sending requests and responses, sometimes network is down,
  /// the socket connection is broken, or so on, and a retry is required.
  /// [sendRequest] and [sendResponse] will try to send the notification up to
  /// [maxSendAttempts] times before giving up, pausing for 200
  /// milliseconds before its first retry, 1 second before its second retry
  /// and 5 seconds before its third (and every subsequent) retry. The
  /// default value of 4 means a total maximum of 4 attempts - i.e. a first
  /// attempt and 3 retries
  int maxSendAttempts = 4;

  AtRpc(
      {required this.atClient,
      required this.baseNameSpace,
      this.rpcsNameSpace = '__rpcs',
      required this.domainNameSpace,
      required this.callbacks,
      required this.allowList});

  /// Starts listening for notifications of the requests and responses
  /// in the `$domainNameSpace.$rpcsNameSpace.$baseNameSpace` namespace
  void start() {
    logger.info('allowList is $allowList');
    var regex = 'request.\\d+.$domainNameSpace.$rpcsNameSpace.$baseNameSpace@';
    logger.info('Subscribing to $regex');

    _requestStream = atClient.notificationService
        .subscribe(regex: regex, shouldDecrypt: true);

    _requestStream!.listen(handleRequestNotification,
        onError: (e) => logger.severe('Notification Failed: $e'),
        onDone: () => logger.info('RPC request listener stopped'));

    regex =
        '(success|error|ack|nack).\\d+.$domainNameSpace.$rpcsNameSpace.$baseNameSpace@';
    logger.info('Subscribing to $regex');

    _responseStream = atClient.notificationService
        .subscribe(regex: regex, shouldDecrypt: true);

    _responseStream!.listen(handleResponseNotification,
        onError: (e) => logger.severe('Notification Failed: $e'),
        onDone: () => logger.info('RPC response listener stopped'));
  }

  /// Sends a request by sending a notification with 'key' of
  /// `request.${request.reqId}.$domainNameSpace.$rpcsNameSpace.$baseNameSpace`
  /// with payload of `jsonEncode([request].toJson())`
  /// to [toAtSign]
  Future<void> sendRequest(
      {required String toAtSign, required AtRpcReq request}) async {
    toAtSign = AtUtils.fixAtSign(toAtSign);
    String requestRecordIDName =
        'request.${request.reqId}.$domainNameSpace.$rpcsNameSpace';
    var requestRecordID = AtKey()
      ..key = requestRecordIDName
      ..sharedBy = atClient.getCurrentAtSign()
      ..sharedWith = AtUtils.fixAtSign(toAtSign)
      ..namespace = baseNameSpace
      ..metadata = _defaultMetaData;

    // Need to be able to receive responses from the atSigns we're sending requests to
    allowList.add(toAtSign);

    var requestJson = jsonEncode(request.toJson());
    bool sent = false;
    int delayMillis = 200;
    for (int attemptNumber = 1;
        attemptNumber <= maxSendAttempts && !sent;
        attemptNumber++) {
      try {
        logger.info(
            'Sending notification ${requestRecordID.toString()} with payload $requestJson');
        await atClient.notificationService.notify(
            NotificationParams.forUpdate(requestRecordID,
                value: requestJson,
                notificationExpiry: defaultNotificationExpiry),
            checkForFinalDeliveryStatus: false,
            waitForFinalDeliveryStatus: false);
        sent = true;
        logger.info('Notification ${requestRecordID.toString()} sent');
      } catch (e) {
        if (attemptNumber < maxSendAttempts) {
          logger.warning(
              'Exception $e sending request $request on attempt $attemptNumber - will retry in $delayMillis ms');
        } else {
          logger.severe(
              'Exception $e sending request $request on attempt $attemptNumber - giving up');
        }
        await Future.delayed(Duration(milliseconds: delayMillis));
        if (delayMillis < 5000) {
          delayMillis *= 5;
        }
      }
    }
  }

  // ***********************************************************************
  // *** Everything below this point is not part of the public AtRpc API ***
  // ***********************************************************************

  final Metadata _defaultMetaData = Metadata()
    ..isPublic = false
    ..isEncrypted = true
    ..namespaceAware = true;

  /// Not part of API, but visibleForTesting.
  /// Receives 'request' notifications, and
  /// - parses and validates
  /// - sends an [AtRpcRespType.nack] response if deserialization or validation fails
  /// - sends an [AtRpcRespType.nack] response otherwise
  /// - calls [AtRpcCallbacks.handleRequest]
  /// - calls [sendResponse] with the response from [AtRpcCallbacks.handleRequest]
  @visibleForTesting
  Future<void> handleRequestNotification(AtNotification notification) async {
    if (!allowList.contains(notification.from)) {
      logger.info(
          'Ignoring notification from non-allowed atSign ${notification.from} : $notification');
      return;
    }

    // request key should be like:
    // @toAtSign:request.<id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@fromAtSign
    // strip off the prefix `@toAtSign:request.`
    String requestKey =
        notification.key.replaceFirst('${notification.to}:request.', '');
    // We should now have something like:
    // <id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@fromAtSign
    // We want to keep just the <id> and discard the rest
    requestKey = requestKey.replaceAll(
        '.$domainNameSpace.$rpcsNameSpace.$baseNameSpace${notification.from}',
        '');

    int requestId = -1;
    try {
      requestId = int.parse(requestKey);
    } catch (e) {
      logger.warning('Failed to get request ID from ${notification.key} - $e');
      return;
    }

    // print('Received request with id ${notification.key} and value ${chalk.brightGreen.bold(notification.value)}');
    late AtRpcReq request;

    try {
      request = AtRpcReq.fromJson(jsonDecode(notification.value!));
    } catch (e, st) {
      var message =
          'Failed to deserialize AtRpcReq from ${notification.value}: $e';
      logger.warning(message);
      logger.warning(st);
      // send NACK
      await sendResponse(notification, request,
          AtRpcResp.nack(request: request, message: message));
      return;
    }

    if (request.reqId != requestId) {
      var message =
          'Ignoring request: requestID from the notification key $requestId'
          ' does not match requestID from notification payload ${request.reqId}';
      logger.warning(message);
      // send NACK
      await sendResponse(notification, request,
          AtRpcResp.nack(request: request, message: message));
      return;
    }

    // send ACK
    await sendResponse(notification, request, AtRpcResp.ack(request: request));

    late AtRpcResp response;
    try {
      response = await callbacks.handleRequest(request, notification.from);
      await sendResponse(notification, request, response);
    } catch (e, st) {
      var message =
          'Exception $e from callbacks.handleRequest for request $request';
      logger.warning(message);
      logger.warning(st);
      await sendResponse(notification, request,
          AtRpcResp.nack(request: request, message: message));
    }
  }

  /// Not part of API, but visibleForTesting.
  /// Receives 'response' notifications, and
  /// - parses and validates
  /// - logs warnings if deserialization or validation fails
  /// - calls [AtRpcCallbacks.handleResponse] otherwise
  @visibleForTesting
  Future<void> handleResponseNotification(AtNotification notification) async {
    if (!allowList.contains(notification.from)) {
      logger.info(
          'Ignoring notification from non-allowed atSign ${notification.from} : $notification');
      return;
    }

    // response key should be like:
    // @toAtSign:<ack|nack|success|error>.<id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@fromAtSign
    // strip off the prefix `@toAtSign:<ack|nack|success|error>.`
    String requestKey = notification.key
        .replaceFirst('${notification.to}:', '')
        .replaceFirst(RegExp(r'(success|error|ack|nack)\.'), '');
    // We should now have something like:
    // <id>.<domainNameSpace>.<rpcsNameSpace>.<baseNameSpace>@fromAtSign
    // We want to keep just the <id> and discard the rest
    requestKey = requestKey.replaceAll(
        '.$domainNameSpace.$rpcsNameSpace.$baseNameSpace${notification.from}',
        '');

    int requestId = -1;
    try {
      requestId = int.parse(requestKey);
    } catch (e) {
      logger.warning('Failed to get request ID from ${notification.key} - $e');
      return;
    }

    late AtRpcResp response;

    try {
      response = AtRpcResp.fromJson(jsonDecode(notification.value!));
    } catch (e, st) {
      var message =
          'Failed to deserialize AtRpcResp from ${notification.value}: $e';
      logger.warning(message);
      logger.warning(st);
      return;
    }

    if (response.reqId != requestId) {
      var message =
          'Ignoring response: requestID from the notification key $requestId'
          ' does not match requestID from the response notification payload ${response.reqId}';
      logger.warning(message);
      return;
    }

    try {
      await callbacks.handleResponse(response);
    } catch (e, st) {
      logger.warning(
          'Exception $e from callbacks.handleResponse for response $response');
      logger.warning(st);
    }
  }

  /// Not part of API, but visibleForTesting.
  /// Sends a response. Note that this is marked as `@visibleForTesting` as it
  /// is only called by [handleRequestNotification] and is not intended to be
  /// used directly by [AtRpc] users.
  @visibleForTesting
  Future<void> sendResponse(
      AtNotification notification, AtRpcReq request, AtRpcResp response) async {
    bool sent = false;
    int delayMillis = 200;
    for (int attemptNumber = 1;
        attemptNumber <= maxSendAttempts && !sent;
        attemptNumber++) {
      try {
        String responseAtID =
            '${response.respType.name}.${request.reqId}.$domainNameSpace.$rpcsNameSpace';
        var responseAtKey = AtKey()
          ..key = responseAtID
          ..sharedBy = atClient.getCurrentAtSign()
          ..sharedWith = notification.from
          ..namespace = baseNameSpace
          ..metadata = _defaultMetaData;

        logger.info(
            "Sending notification $responseAtKey with payload ${response.toJson()}");
        await atClient.notificationService.notify(
            NotificationParams.forUpdate(responseAtKey,
                value: jsonEncode(response.toJson()),
                notificationExpiry: defaultNotificationExpiry),
            checkForFinalDeliveryStatus: false,
            waitForFinalDeliveryStatus: false);
        sent = true;
      } catch (e) {
        if (attemptNumber < maxSendAttempts) {
          logger.warning(
              'Exception $e sending response $response on attempt $attemptNumber - will retry in $delayMillis ms');
        } else {
          logger.severe(
              'Exception $e sending response $response on attempt $attemptNumber - giving up');
        }
        await Future.delayed(Duration(milliseconds: delayMillis));
        if (delayMillis < 5000) {
          delayMillis *= 5;
        }
      }
    }
  }
}
