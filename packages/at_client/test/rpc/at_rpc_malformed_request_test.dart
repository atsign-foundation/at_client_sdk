import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';
import '../test_utils/recorded_logs.dart';

class _MockAtClient extends Mock implements AtClient {}

class _MockNotificationService extends Mock implements NotificationService {}

class _Callbacks implements AtRpcCallbacks {
  final List<AtRpcReq> requests = [];
  final List<AtRpcResp> responses = [];

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
    requests.add(request);
    return AtRpcResp(
        reqId: request.reqId,
        respType: AtRpcRespType.success,
        payload: {'answer': 42});
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async =>
      responses.add(response);
}

/// An allow list whose first membership check fails, as one backed by
/// something else can.
class _ContainsThrowsOnce extends SetBase<String> {
  _ContainsThrowsOnce(this._inner);

  final Set<String> _inner;
  bool _thrown = false;

  @override
  bool contains(Object? element) {
    if (!_thrown) {
      _thrown = true;
      throw StateError('the allow list could not be read');
    }
    return _inner.contains(element);
  }

  @override
  bool add(String value) => _inner.add(value);

  @override
  Iterator<String> get iterator => _inner.iterator;

  @override
  int get length => _inner.length;

  @override
  String? lookup(Object? element) => _inner.lookup(element);

  @override
  bool remove(Object? value) => _inner.remove(value);

  @override
  Set<String> toSet() => _inner.toSet();
}

void main() {
  final logs = RecordedLogs();

  late _MockAtClient atClient;
  late _Callbacks callbacks;
  late List<NotificationParams> sent;
  late List<String> mutexes;
  late StreamController<AtNotification> incoming;

  setUpAll(() {
    logs.installOn(level: 'warning');
    registerFallbackValue(NotificationParams());
    registerFallbackValue(AtKey());
    registerFallbackValue(PutRequestOptions());
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  setUp(() {
    logs.records.clear();
    atClient = _MockAtClient();
    final notifications = _MockNotificationService();
    callbacks = _Callbacks();
    sent = [];
    mutexes = [];
    incoming = StreamController<AtNotification>();
    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
    when(() => atClient.notificationService).thenReturn(notifications);
    when(() => atClient.isStopped).thenReturn(false);
    final remote = MockRemoteSecondary();
    when(() => atClient.enrollmentId).thenReturn('e-1');
    when(() => atClient.getRemoteSecondary()).thenReturn(remote);
    when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as VerbBuilder;
      if (builder is! UpdateVerbBuilder) {
        throw StateError('unexpected verb: ${builder.runtimeType}');
      }
      mutexes.add('${builder.atKey}');
      return 'data:-1';
    });
    when(() => notifications.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => incoming.stream);
    when(() => notifications.notify(any(),
        checkForFinalDeliveryStatus: any(named: 'checkForFinalDeliveryStatus'),
        waitForFinalDeliveryStatus: any(named: 'waitForFinalDeliveryStatus'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
        onSentToSecondary: any(named: 'onSentToSecondary'))).thenAnswer((inv) {
      sent.add(inv.positionalArguments[0] as NotificationParams);
      return Future.value(NotificationResult());
    });
  });

  // NOTE: not awaited; a controller nothing ever listened to never finishes
  // closing.
  tearDown(() {
    unawaited(incoming.close());
  });

  AtRpc responder(
          {Set<String>? allowList,
          bool allowAll = false,
          bool enableRequestMutex = false}) =>
      AtRpc(
          atClient: atClient,
          baseNameSpace: 'testing',
          domainNameSpace: 'malformed',
          callbacks: callbacks,
          allowList: allowList ?? {'@bob'},
          allowAll: allowAll,
          isClient: false,
          isServer: true,
          enableRequestMutex: enableRequestMutex);

  AtRpc requester({required Set<String> allowList}) => AtRpc(
      atClient: atClient,
      baseNameSpace: 'testing',
      domainNameSpace: 'malformed',
      callbacks: callbacks,
      allowList: allowList,
      isClient: true,
      isServer: false);

  AtNotification request(int id, String? value, {String from = '@bob'}) =>
      AtNotification.empty()
        ..id = 'n-$id'
        ..key = '@alice:request.$id.malformed.__rpcs.testing$from'
        ..from = from
        ..to = '@alice'
        ..value = value;

  AtNotification response(int id) => AtNotification.empty()
    ..id = 'r-$id'
    ..key = '@alice:success.$id.malformed.__rpcs.testing@bob'
    ..from = '@bob'
    ..to = '@alice'
    ..value = jsonEncode(
        AtRpcResp(reqId: id, respType: AtRpcRespType.success, payload: {})
            .toJson());

  String valid(int id) => jsonEncode(AtRpcReq(reqId: id, payload: {}).toJson());

  List<String> sentKeys() => [for (final p in sent) p.atKey.toString()];

  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out: sent ${sentKeys()}, handled ${callbacks.requests}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await pumpEventQueue();
  }

  // NOTE: the NACK's key and value are what the requester parses, so they are
  // pinned as raw literals.
  const nackKey = '@bob:nack.7.malformed.__rpcs.testing@alice';
  const nackValue = '{"reqId":7,"respType":"nack","payload":{},'
      '"message":"The request could not be parsed as an AtRpcReq"}';

  group(
      'Given a responder and a request from an allowed atSign whose value is '
      'not an AtRpcReq', () {
    test(
        'when the value is not JSON, then it is answered with a NACK under the '
        'id in its key, and the handler is not called', () async {
      await responder().handleRequestNotification(request(7, 'not json'));

      expect(sentKeys(), [nackKey]);
      expect(sent.single.value, nackValue);
      expect(callbacks.requests, isEmpty);
    });

    test(
        'when the value is JSON of the wrong shape, then it is answered the '
        'same way', () async {
      for (final value in [
        '{"unexpected":"shape"}',
        '[1]',
        '{"reqId":"7","payload":{}}',
        '{"reqId":7,"payload":null}',
      ]) {
        sent.clear();
        await responder().handleRequestNotification(request(7, value));

        expect(sentKeys(), [nackKey], reason: 'value $value');
        expect(sent.single.value, nackValue, reason: 'value $value');
      }
      expect(callbacks.requests, isEmpty);
    });

    test('when the notification has no value, then it is answered the same way',
        () async {
      await responder().handleRequestNotification(request(7, null));

      expect(sentKeys(), [nackKey]);
      expect(sent.single.value, nackValue);
      expect(callbacks.requests, isEmpty);
    });

    test('when request mutexes are on, then the NACK takes no mutex', () async {
      final rpc = responder(enableRequestMutex: true);

      await rpc.handleRequestNotification(request(7, 'not json'));
      expect(sentKeys(), [nackKey]);
      expect(mutexes, isEmpty,
          reason: 'a request that cannot be parsed writes nothing to the '
              'atServer');

      await rpc.handleRequestNotification(request(8, valid(8)));
      expect(mutexes, hasLength(1),
          reason: 'control: a valid request does take its mutex');
    });

    test(
        'when it arrives through start() followed by a valid request, then the '
        'valid one is answered and handled, and no error reaches the zone',
        () async {
      final uncaught = <Object>[];
      final rpc = responder();
      runZonedGuarded(rpc.start, (e, _) => uncaught.add(e));

      incoming.add(request(7, 'not json'));
      incoming.add(request(8, valid(8)));
      await until(() => sent.length == 3);

      expect(uncaught, isEmpty);
      expect(
          sentKeys(),
          unorderedEquals([
            nackKey,
            '@bob:ack.8.malformed.__rpcs.testing@alice',
            '@bob:success.8.malformed.__rpcs.testing@alice',
          ]));
      expect([for (final r in callbacks.requests) r.reqId], [8]);
    });

    test(
        'when the sender is not on the allow list and allowAll is false, then '
        'nothing is sent', () async {
      await responder()
          .handleRequestNotification(request(7, 'not json', from: '@carol'));

      expect(sent, isEmpty);
    });
  });

  group('Given a started AtRpc whose handler throws', () {
    test(
        'when a request handler throws past its own catches, then the error is '
        'logged and later requests are still served', () async {
      final uncaught = <Object>[];
      final rpc = responder(allowList: _ContainsThrowsOnce({'@bob'}));
      runZonedGuarded(rpc.start, (e, _) => uncaught.add(e));

      incoming.add(request(7, valid(7)));
      incoming.add(request(8, valid(8)));
      await until(() => sent.length == 2);

      expect(uncaught, isEmpty);
      expect(
          logs.at('SEVERE'),
          contains(allOf(contains('the allow list could not be read'),
              contains('request.7.malformed'))));
      expect([for (final r in callbacks.requests) r.reqId], [8]);
    });

    test(
        'when a response handler throws, then the error is logged and later '
        'responses are still handled', () async {
      final uncaught = <Object>[];
      final rpc = requester(allowList: _ContainsThrowsOnce({'@bob'}));
      runZonedGuarded(rpc.start, (e, _) => uncaught.add(e));

      incoming.add(response(7));
      incoming.add(response(8));
      await until(() => callbacks.responses.isNotEmpty);

      expect(uncaught, isEmpty);
      expect(
          logs.at('SEVERE'),
          contains(allOf(contains('the allow list could not be read'),
              contains('success.7.malformed'))));
      expect([for (final r in callbacks.responses) r.reqId], [8]);
    });
  });
}
