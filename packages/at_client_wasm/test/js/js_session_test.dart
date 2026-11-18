import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/src/collections/js_collections_adapter.dart';
import 'package:at_client_wasm/src/js/js_session.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

class _FakeNotifications extends Fake implements NotificationService {
  final events = StreamController<AtNotification>.broadcast();
  final params = <NotificationParams>[];
  var status = NotificationStatusEnum.delivered;
  AtClientException? exception;
  String? lastRegex;
  bool? lastShouldDecrypt;
  var starts = 0;
  var nextId = 0;

  /// Whether `notify` reports the id through `onSentToSecondary`, as the real
  /// service does before it waits for a final status.
  var reportsSent = true;

  /// When set, `notify` waits for it after reporting the send.
  Completer<void>? hold;

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {bool waitForFinalDeliveryStatus = true,
      bool checkForFinalDeliveryStatus = true,
      bool encryptValue = true,
      Function(NotificationResult)? onSuccess,
      Function(NotificationResult)? onError,
      Function(NotificationResult)? onSentToSecondary}) async {
    params.add(notificationParams);
    final result = NotificationResult()
      ..notificationID = 'n${nextId++}'
      ..notificationStatusEnum = status
      ..atClientException = exception;
    if (reportsSent) onSentToSecondary?.call(result);
    await hold?.future;
    return result;
  }

  @override
  Stream<AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    lastRegex = regex;
    lastShouldDecrypt = shouldDecrypt;
    return events.stream;
  }

  @override
  void startListening() => starts++;
}

class _FakeClient extends Fake implements AtClient {
  var stops = 0;

  @override
  final AtConnection connection = AtConnection(
      atSign: '@alice', attempt: (_) async => AtConnectionState.online());

  @override
  final _FakeNotifications notificationService = _FakeNotifications();

  @override
  String? getCurrentAtSign() => '@alice';

  @override
  Future<void> stop() async => stops++;
}

AtNotification _event(String id,
        {String value = 'yo',
        String? operation = 'update',
        String key = '@alice:attalk.wavi@bob',
        String from = '@bob'}) =>
    AtNotification(id, key, from, '@alice', 42, 'key', true,
        value: value, operation: operation);

/// A notification this session's own atSign sent, as the atServer echoes it.
AtNotification _echo(String id) =>
    _event(id, key: 'k.attalk.wavi@alice', from: '@alice');

void main() {
  late _FakeClient client;
  late AtClientJsSession session;
  late _FakeNotifications service;
  late List<String> warnings;
  late bool navigatorOnline;

  setUp(() {
    client = _FakeClient();
    service = client.notificationService;
    warnings = [];
    navigatorOnline = true;
    session = AtClientJsSession(client,
        namespace: 'wavi',
        warn: warnings.add,
        isNavigatorOnline: () => navigatorOnline);
  });

  group('keys', () {
    // notify is the only call that takes a key until the collections surface
    // lands, so these go through it; each key is shared, as notify requires.
    Future<String> sentKey(JsKey key) async {
      await session.notify(key, 'v');
      return service.params.last.atKey.toString();
    }

    test('a shared key is <key>.<namespace> by the own atSign', () async {
      expect(await sentKey(const JsKey('k', sharedWith: '@bob')),
          '@bob:k.wavi@alice');
      expect(service.params.last.atKey.metadata.namespaceAware, isFalse);
    });

    test('a given namespace replaces the default', () async {
      expect(
          await sentKey(
              const JsKey('k', namespace: 'other', sharedWith: '@bob')),
          '@bob:k.other@alice');
    });

    test('an explicit sharedBy is kept', () async {
      await session.notify(
          const JsKey('k', sharedWith: '@bob', sharedBy: '@carol'), 'v');

      expect(service.params.last.atKey.sharedBy, '@carol');
    });

    test('noNamespace leaves the session namespace off', () async {
      expect(
          await sentKey(
              const JsKey('k', sharedWith: '@bob', noNamespace: true)),
          '@bob:k@alice');
    });

    test('an atSign without @ is put in @name form', () async {
      await session.notify(const JsKey('k', sharedWith: 'bob'), 'v');

      expect(service.params.last.atKey.sharedWith, '@bob');
    });
  });

  group('notify', () {
    test('without sharedWith it is a bad key and sends nothing', () async {
      await expectLater(session.notify(const JsKey('k'), 'v'),
          throwsA(isA<BadKeyException>()));
      expect(service.params, isEmpty);
    });

    test('sends an update on the shared key, outside the app namespace',
        () async {
      final sent = await session.notify(
          const JsKey('rpc', namespace: 'tally', sharedWith: '@bob'), 'hi');

      expect(sent, isTrue);
      final params = service.params.single;
      expect(params.atKey.toString(), '@bob:rpc.tally@alice');
      expect(params.atKey.metadata.namespaceAware, isFalse);
      expect(params.operation, OperationEnum.update);
      expect(params.value, 'hi');
    });

    test('resolves false when the notification is not delivered', () async {
      service.status = NotificationStatusEnum.undelivered;

      expect(await session.notify(const JsKey('k', sharedWith: '@bob'), 'v'),
          isFalse);
    });

    test('rethrows the exception an undelivered notification carries',
        () async {
      final cause = AtClientException('AT0001', 'Unable to connect');
      service
        ..status = NotificationStatusEnum.undelivered
        ..exception = cause;

      await expectLater(
          session.notify(const JsKey('k', sharedWith: '@bob'), 'v'),
          throwsA(same(cause)));
    });
  });

  group('subscribe', () {
    test('subscribes decrypted, starts the monitor and delivers events',
        () async {
      final received = <JsNotification>[];

      session.subscribe(r'attalk\.wavi@', received.add, onError: (_) {});

      expect(service.lastRegex, r'attalk\.wavi@');
      expect(service.lastShouldDecrypt, isTrue);
      expect(service.starts, 1);

      service.events.add(_event('e1'));
      await pumpEventQueue();
      expect(received.single, (
        id: 'e1',
        from: '@bob',
        key: '@alice:attalk.wavi@bob',
        value: 'yo',
        epochMillis: 42,
        operation: 'update',
      ));
    });

    test('names a delete notification a delete, anything else an update',
        () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events.add(_event('d1', operation: 'delete'));
      service.events.add(_event('d2', operation: 'update'));
      service.events.add(_event('d3', operation: null));
      await pumpEventQueue();

      expect(received.map((n) => n.operation), ['delete', 'update', 'update']);
    });

    test('unsubscribe stops delivery', () async {
      final received = <JsNotification>[];
      final unsubscribe = session.subscribe('.*', received.add, onError: (_) {});

      unsubscribe();
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test('delivers only a notification sent by the key owner', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events
        ..add(_event('other', from: '@carol'))
        ..add(_event('own', from: '@bob'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['own']);
    });

    test('matches the sender and the key owner by canonical atSign', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events
        ..add(_event('a', from: 'BOB'))
        ..add(_event('b', key: '@alice:attalk.wavi@BOB', from: '@bob'))
        ..add(_event('c', key: 'public:k@bob', from: ' Bob '))
        ..add(_event('d', key: 'nokey', from: '@bob'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['a', 'b', 'c']);
      expect(received.map((n) => n.from), everyElement('@bob'));
    });

    test('drops the echo of a notification this session sent', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      await session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      service.events
        ..add(_echo('n0'))
        ..add(_event('other'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['other']);
    });

    test('delivers a peer notification that reuses an id this session sent',
        () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      await session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      service.events
        ..add(_event('n0', key: '@alice:attalk.wavi@bob', from: '@bob'))
        ..add(_echo('n0'));
      await pumpEventQueue();

      expect(received.map((n) => (n.id, n.from)), [('n0', '@bob')]);
    });

    test('drops an echo that arrives before notify resolves', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});
      service.hold = Completer<void>();
      final pending =
          session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      await pumpEventQueue();
      service.events.add(_echo('n0'));
      await pumpEventQueue();
      service.hold!.complete();
      await pending;

      expect(received, isEmpty);
    });

    test('remembers only the last 1024 sent ids', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      for (var i = 0; i < 1025; i++) {
        await session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      }
      service.events
        ..add(_echo('n0'))
        ..add(_echo('n1'))
        ..add(_echo('n1024'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['n0']);
    });
  });

  group('subscribe errors and drops', () {
    test('a stream error reaches onError and the subscription survives',
        () async {
      final received = <JsNotification>[];
      final errors = <Object>[];
      session.subscribe('.*', received.add, onError: errors.add);

      service.events.addError(StateError('monitor down'));
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(errors.single, isA<StateError>());
      expect(received.map((n) => n.id), ['e1']);
    });

    test('a notification whose sender is not the key owner is dropped with '
        'a warning naming its id, never its value', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events.add(_event('spoofed', from: '@carol', value: 'secret-v'));
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(warnings.single, contains('spoofed'));
      expect(warnings.single, isNot(contains('secret-v')));
    });

    test('an echo of this session is dropped without a warning', () async {
      session.subscribe('.*', (_) {}, onError: (_) {});

      await session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      service.events.add(_echo('n0'));
      await pumpEventQueue();

      expect(warnings, isEmpty);
    });
  });

  group('status', () {
    Future<void> report(AtConnectionState state) async {
      await client.connection.report(state);
      await pumpEventQueue();
    }

    test('starts connecting while nothing has been attempted', () {
      expect(session.status, 'connecting');
    });

    final cases = <String, (AtConnectionState, bool, String)>{
      'online': (AtConnectionState.online(), true, 'connected'),
      'unreachable with the browser online': (
        AtConnectionState.offline(AtConnectionCause.unreachable),
        true,
        'waiting:server'
      ),
      'unreachable with the browser offline': (
        AtConnectionState.offline(AtConnectionCause.unreachable),
        false,
        'waiting:network'
      ),
      'no atServer': (
        AtConnectionState.offline(AtConnectionCause.noAtServer),
        true,
        'waiting:server'
      ),
      'revoked': (
        AtConnectionState.refused(AtConnectionCause.revoked),
        true,
        'waiting:auth'
      ),
      'unauthenticated': (
        AtConnectionState.refused(AtConnectionCause.unauthenticated),
        true,
        'waiting:auth'
      ),
      'enrollment not approved': (
        AtConnectionState.refused(AtConnectionCause.enrollmentNotApproved),
        true,
        'waiting:auth'
      ),
    };
    for (final MapEntry(key: name, value: (state, onLine, status))
        in cases.entries) {
      test('$name is $status', () async {
        navigatorOnline = onLine;
        await report(state);
        expect(session.status, status);
      });
    }

    test('onStatus reports each change, latest wins, and off stops it',
        () async {
      final seen = <String>[];
      final off = session.onStatus(seen.add);

      await report(AtConnectionState.online());
      await report(AtConnectionState.offline(AtConnectionCause.unreachable));
      off();
      await report(AtConnectionState.online());

      expect(seen, ['connected', 'waiting:server']);
      expect(session.status, 'connected');
    });

    test('close ends the reporting and keeps the last status', () async {
      await report(AtConnectionState.online());
      final seen = <String>[];
      session.onStatus(seen.add);

      await session.close();
      await client.connection.report(AtConnectionState.offline(
          AtConnectionCause.stopped));
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(session.status, 'connected');
    });

    test('onStatus after close throws SessionClosedException', () async {
      await session.close();
      expect(() => session.onStatus((_) {}),
          throwsA(isA<SessionClosedException>()));
    });
  });

  group('collection', () {
    test('after close throws SessionClosedException', () async {
      await session.close();
      await expectLater(session.collection('todos', type: 'Todo'),
          throwsA(isA<SessionClosedException>()));
    });

    test('qualifies the name with the namespace and rejects a bad expiration '
        'with the adapter code', () async {
      await expectLater(
          session.collection('todos', type: 'Todo', expirationMs: 0),
          throwsA(isA<JsCollectionsError>().having(
              (e) => e.code, 'code', CollectionErrorCodes.invalidArgument)));
    });

    test('a name already ending in the namespace is kept', () {
      expect(AtClientJsSession.qualified('todos.wavi', 'wavi'), 'todos.wavi');
      expect(AtClientJsSession.qualified('todos', 'wavi'), 'todos.wavi');
    });
  });

  group('close', () {
    test('stops the client once', () async {
      await session.close();
      await session.close();

      expect(client.stops, 1);
    });

    test('every call after it throws SessionClosedException', () async {
      await session.close();

      for (final call in <Future<Object?> Function()>[
        () => session.notify(const JsKey('k', sharedWith: '@bob'), 'v'),
        () async => session.subscribe('.*', (_) {}, onError: (_) {}),
      ]) {
        await expectLater(call(), throwsA(isA<SessionClosedException>()));
      }
    });

    test('stops delivering to subscribers', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      await session.close();
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(received, isEmpty);
    });
  });
}
