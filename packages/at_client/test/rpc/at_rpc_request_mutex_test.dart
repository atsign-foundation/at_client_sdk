import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _MockNotificationService extends Mock implements NotificationService {}

class _Callbacks implements AtRpcCallbacks {
  int handled = 0;

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
    handled++;
    return AtRpcResp.ack(request: request);
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async {}
}

/// A responder with the request mutex on handles a request only when it is
/// the one responder of its atSign to take that request's lock.
void main() {
  AtSignLogger.root_level = 'shout';

  setUpAll(() {
    registerFallbackValue(NotificationParams());
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  late List<String> commands;
  late _Callbacks callbacks;

  /// A responder for @alice whose atServer answers a lock create with
  /// [onCreate], recording every command it is sent.
  AtRpc responder(
      {bool enableRequestMutex = true, Future<String> Function()? onCreate}) {
    final atClient = MockAtClient();
    final remote = MockRemoteSecondary();
    final notifications = _MockNotificationService();
    commands = [];
    callbacks = _Callbacks();
    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => atClient.enrollmentId).thenReturn('e-1');
    when(() => atClient.getRemoteSecondary()).thenReturn(remote);
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.isStopped).thenReturn(false);
    when(() => remote.executeVerb(any())).thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as VerbBuilder;
      commands.add(builder.buildCommand());
      if (builder is! UpdateVerbBuilder) {
        throw StateError('unexpected verb: ${builder.runtimeType}');
      }
      return (onCreate ?? () async => 'data:-1')();
    });
    when(() => notifications.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary:
            any(named: 'onSentToSecondary'))).thenAnswer(
        (_) async => NotificationResult());
    return AtRpc(
        atClient: atClient,
        baseNameSpace: 'testing',
        domainNameSpace: 'mutex',
        callbacks: callbacks,
        allowList: {'@bob'.toAtsign()},
        isClient: false,
        isServer: true,
        enableRequestMutex: enableRequestMutex);
  }

  AtNotification requestFromBob(int id) => AtNotification.empty()
    ..id = 'n-$id'
    ..key = '@alice:request.$id.mutex.__rpcs.testing@bob'
    ..from = '@bob'
    ..to = '@alice'
    ..value = jsonEncode(AtRpcReq(reqId: id, payload: {'q': 1}).toJson());

  test(
      'a request is handled once its mutex is taken, by a create that '
      'records no commit', () async {
    await responder().handleRequestNotification(requestFromBob(42));

    expect(commands, [
      'update:nc:ttl:30000:isEncrypted:false:immutable:true:'
          '42.session_mutexes.mutex.__rpcs.testing@alice e-1\n'
    ]);
    expect(callbacks.handled, 1);
  });

  test('a request whose mutex another responder holds is not handled',
      () async {
    await responder(
            onCreate: () async => throw IllegalStateException(
                'Immutable records may not be updated'))
        .handleRequestNotification(requestFromBob(43));

    expect(commands, hasLength(1));
    expect(callbacks.handled, 0);
  });

  test(
      'a request whose mutex cannot be taken for another reason is not '
      'handled', () async {
    await responder(onCreate: () async => throw AtTimeoutException('no answer'))
        .handleRequestNotification(requestFromBob(44));

    expect(commands, hasLength(1));
    expect(callbacks.handled, 0);
  });

  test('with the mutex off, a request is handled and nothing is written',
      () async {
    await responder(enableRequestMutex: false)
        .handleRequestNotification(requestFromBob(45));

    expect(commands, isEmpty);
    expect(callbacks.handled, 1);
  });
}
