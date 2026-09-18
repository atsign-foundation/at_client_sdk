import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockNotificationService extends Mock implements NotificationService {}

class _Callbacks implements AtRpcCallbacks {
  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async =>
      AtRpcResp.ack(request: request);

  @override
  Future<void> handleResponse(AtRpcResp response) async {}
}

/// The far side answers over the caller's notification listener, and nothing
/// replays an answer that arrives with nothing subscribed, so
/// [AtRpc.sendRequest] waits for [AtRpc.ready] before it sends.
void main() {
  AtSignLogger.root_level = 'shout';

  late AtClient atClient;
  late _MockNotificationService notifications;
  late StreamController<NotificationListenerState> states;
  late List<AtKey> notified;

  setUpAll(() => registerFallbackValue(NotificationParams()));

  setUp(() {
    atClient = _MockAtClient();
    notifications = _MockNotificationService();
    states = StreamController<NotificationListenerState>.broadcast();
    notified = [];

    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => notifications.currentListenerStateStream)
        .thenAnswer((_) => states.stream);
    when(() => notifications.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary: any(named: 'onSentToSecondary'))).thenAnswer((inv) {
      notified.add((inv.positionalArguments[0] as NotificationParams).atKey);
      return Future.value(NotificationResult());
    });
  });

  tearDown(() async {
    if (!states.isClosed) await states.close();
  });

  AtRpc rpcFor({required bool isClient}) => AtRpc(
      atClient: atClient,
      baseNameSpace: 'testing',
      domainNameSpace: 'readiness',
      callbacks: _Callbacks(),
      allowList: {},
      isClient: isClient,
      isServer: !isClient);

  test('sendRequest waits for the listener before it notifies', () async {
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.notConnected);
    final AtRpc rpc = rpcFor(isClient: true);

    final Future<void> sending =
        rpc.sendRequest(toAtSign: '@bob', request: AtRpcReq.create({'q': 1}));

    // NOTE: pumped rather than merely checked — an unpumped assertion passes
    // for a `sendRequest` with no wait in it.
    await Future<void>.delayed(Duration(milliseconds: 50));
    expect(notified, isEmpty,
        reason: 'the far side answers over the notification listener, so '
            'nothing may go out while that listener is still connecting');

    states.add(NotificationListenerState.listening);
    await sending;
    expect(notified, hasLength(1));
    expect(notified.single.key, startsWith('request.'),
        reason: 'and once the listener is up the request is the thing sent');
  });

  test('a listener already up is not waited for', () async {
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.listening);
    final AtRpc rpc = rpcFor(isClient: true);

    // NOTE: no event is ever pushed onto `states`, so this passes only because
    // the current state is read as well as the stream.
    await rpc
        .sendRequest(toAtSign: '@bob', request: AtRpcReq.create({'q': 2}))
        .timeout(Duration(seconds: 5));
    expect(notified, hasLength(1));
  });

  test('a caller that is not listening for responses does not wait', () async {
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.notConnected);
    final AtRpc rpc = rpcFor(isClient: false);

    // NOTE: isServer-only, so it has no response listener to wait on and
    // waiting would deadlock it.
    await rpc
        .sendRequest(toAtSign: '@bob', request: AtRpcReq.create({'q': 3}))
        .timeout(Duration(seconds: 5));
    expect(notified, hasLength(1));
  });

  test('a listener that ends while waited for ends the wait as stopped',
      () async {
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.notConnected);
    final AtRpc rpc = rpcFor(isClient: true);

    final ready = expectLater(rpc.ready(), throwsA(isA<StoppedException>()));
    await Future<void>.delayed(Duration(milliseconds: 20));
    await states.close();

    await ready.timeout(Duration(seconds: 5),
        onTimeout: () => fail('waited out the readiness timeout'));
  });

  test('a send on a stopped client is not retried', () async {
    when(() => atClient.isStopped).thenReturn(true);
    when(() => notifications.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary:
            any(named: 'onSentToSecondary'))).thenThrow(
        StoppedException('the lookup for @alice has been closed'));
    final AtRpc rpc = rpcFor(isClient: false);
    final sent = Stopwatch()..start();

    await expectLater(
        rpc.sendRequest(toAtSign: '@bob', request: AtRpcReq.create({'q': 5})),
        throwsA(isA<StoppedException>()));

    expect(sent.elapsed, lessThan(Duration(milliseconds: 150)),
        reason: 'the first retry would wait 200ms for a client that will '
            'never send again');
    verify(() => notifications.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary: any(named: 'onSentToSecondary'))).called(1);
  });

  test('a call still waiting for its response fails when the client stops',
      () async {
    final responses = StreamController<AtNotification>.broadcast();
    when(() => atClient.isStopped).thenReturn(false);
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.listening);
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => responses.stream);
    final client = AtRpcClient(
        serverAtsign: '@bob',
        atClient: atClient,
        baseNameSpace: 'testing',
        domainNameSpace: 'readiness');

    final answered =
        expectLater(client.call({'q': 6}), throwsA(isA<StoppedException>()));
    await Future<void>.delayed(Duration(milliseconds: 20));
    await responses.close();

    await answered.timeout(Duration(seconds: 5),
        onTimeout: () => fail('the call waited for a response that cannot '
            'arrive'));
  });

  test('a listener that never comes up times out rather than hanging',
      () async {
    when(() => notifications.currentListenerState)
        .thenReturn(NotificationListenerState.notConnected);
    final AtRpc rpc = rpcFor(isClient: true)
      ..listenerReadyTimeout = Duration(milliseconds: 100);

    await expectLater(
        rpc.sendRequest(toAtSign: '@bob', request: AtRpcReq.create({'q': 4})),
        throwsA(isA<TimeoutException>()));
    expect(notified, isEmpty,
        reason: 'giving up must not fall through into sending anyway');
  });
}
