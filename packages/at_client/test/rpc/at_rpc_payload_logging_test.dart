import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockNotificationService extends Mock implements NotificationService {}

/// Answers every request with a success carrying [payload].
class _Answers implements AtRpcCallbacks {
  _Answers(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async =>
      AtRpcResp(
          reqId: request.reqId,
          respType: AtRpcRespType.success,
          payload: payload);

  @override
  Future<void> handleResponse(AtRpcResp response) async {}
}

/// What `AtRpc` and `AtRpcClient` log about a request and its response.
void main() {
  const marker = 'rpc-payload-marker-5521';

  setUpAll(() => registerFallbackValue(NotificationParams()));

  AtClient atClient() {
    final client = _MockAtClient();
    final notifications = _MockNotificationService();
    when(() => client.getCurrentAtSign()).thenReturn('@alice');
    when(() => client.getPreferences())
        .thenReturn(AtClientPreference(posture: PqPosture.legacy));
    when(() => client.notificationService).thenReturn(notifications);
    when(() => client.isStopped).thenReturn(false);
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.listening);
    when(() => notifications.currentListenerStateStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        // NOTE: never done, or the caller's listener would end and fail the
        // call before its response arrived.
        .thenAnswer((_) => StreamController<AtNotification>().stream);
    when(() => notifications.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary:
            any(named: 'onSentToSecondary'))).thenAnswer(
        (_) async => NotificationResult());
    return client;
  }

  /// Calls through an [AtRpcClient] and answers the call, an unparsable
  /// request and a response nobody waits for, each carrying [marker]; returns
  /// the call's request id.
  Future<int> exercise() async {
    final client = atClient();
    final caller = AtRpcClient(
        serverAtsign: '@bob',
        atClient: client,
        baseNameSpace: 'testing',
        domainNameSpace: 'logging');
    final answer = caller.call({'question': marker});
    final id = caller.completerMap.keys.single;
    await pumpEventQueue();

    final server = AtRpc(
        atClient: client,
        baseNameSpace: 'testing',
        domainNameSpace: 'logging',
        callbacks: _Answers({'answer': marker}),
        allowList: {'@bob'},
        isClient: false,
        isServer: true);
    await server.handleRequestNotification(AtNotification.empty()
      ..from = '@bob'
      ..to = '@alice'
      ..key = '@alice:request.$id.logging.__rpcs.testing@bob'
      ..value = jsonEncode(AtRpcReq(reqId: id, payload: {'question': marker})));
    await server.handleRequestNotification(AtNotification.empty()
      ..from = '@bob'
      ..to = '@alice'
      ..key = '@alice:request.${id + 1}.logging.__rpcs.testing@bob'
      ..value = '{"question": "$marker"');

    // NOTE: through the notification handler, so the ack and success branches
    // run against the completer the call registered.
    for (final type in [AtRpcRespType.ack, AtRpcRespType.success]) {
      await caller.rpc.handleResponseNotification(AtNotification.empty()
        ..from = '@bob'
        ..to = '@alice'
        ..key = '@alice:${type.name}.$id.logging.__rpcs.testing@bob'
        ..value = jsonEncode(
            AtRpcResp(reqId: id, respType: type, payload: {'answer': marker})));
    }
    expect(await answer, {'answer': marker});

    await caller.handleResponse(AtRpcResp(
        reqId: id,
        respType: AtRpcRespType.success,
        payload: {'answer': marker}));
    return id;
  }

  /// Every line both RPC loggers emit at [level] while [body] runs.
  Future<List<String>> logged(
      String level, Future<void> Function() body) async {
    final loggers = [AtRpc.logger, AtRpcClient.logger];
    final before = [for (final l in loggers) l.logger.level];
    final lines = <String>[];
    final subscriptions = [
      for (final l in loggers)
        l.logger.onRecord
            .listen((record) => lines.add('${record.level} ${record.message}'))
    ];
    for (final l in loggers) {
      l.level = level;
    }
    try {
      await body();
    } finally {
      for (final s in subscriptions) {
        await s.cancel();
      }
      for (var i = 0; i < loggers.length; i++) {
        loggers[i].logger.level = before[i];
      }
    }
    return lines;
  }

  test('at INFO a request and its response are named by id, not by payload',
      () async {
    late int id;
    final lines = await logged('info', () async => id = await exercise());

    expect(lines.where((line) => line.contains(marker)), isEmpty,
        reason: 'INFO keeps the request id, its type and the outcome; a '
            'payload is logged at finest only');
    expect(lines.where((line) => line.contains('$id')), isNotEmpty,
        reason: 'INFO names the request by its id');
  });

  test('at finest the payloads are logged', () async {
    final lines = await logged('finest', exercise);

    expect(lines.where((line) => line.contains(marker)), isNotEmpty,
        reason: 'a run that opts into finest still sees the payloads');
  });
}
