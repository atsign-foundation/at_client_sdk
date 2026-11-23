import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/js_session.dart';
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

  /// When set, `subscribe` returns this stream instead of [events].
  Stream<AtNotification>? customStream;

  /// When set, called synchronously inside [startListening].
  void Function()? onStartListening;

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
    return customStream ?? events.stream;
  }

  @override
  void startListening() {
    starts++;
    onStartListening?.call();
  }
}

class _FakeCollection<T> extends Fake implements AtCollection<T> {
  _FakeCollection(this.namespace);

  @override
  final String namespace;

  var cancels = 0;

  /// When set, cancelling a watch throws it.
  Object? cancelFailure;

  @override
  Stream<CEvent> watch() => (StreamController<CEvent>()
        ..onCancel = () {
          cancels++;
          if (cancelFailure case final failure?) {
            return Future<void>.error(failure);
          }
          return null;
        })
      .stream;
}

class _FakeClient extends Fake implements AtClient {
  var stops = 0;
  Completer<void>? stopHold;

  /// When set, the next `stop` throws it, then clears it.
  Object? stopFailure;

  /// When set, the next collection open throws it, then clears it.
  Object? openFailure;
  final openedCollections = <(String, Duration, EventSource, String?)>[];
  final collections = <_FakeCollection<Object?>>[];

  @override
  final AtConnection connection = AtConnection(
      atSign: '@alice', attempt: (_) async => AtConnectionState.online());

  @override
  final _FakeNotifications notificationService = _FakeNotifications();

  @override
  String? getCurrentAtSign() => '@alice';

  @override
  Future<AtCollection<T>> collection<T>(
    String namespace,
    Duration defaultExpiration, {
    EventSource eventSource = EventSource.both,
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
    String? writeTypeTag,
    bool cleanupOrphansOnCreation = false,
  }) async {
    openedCollections
        .add((namespace, defaultExpiration, eventSource, writeTypeTag));
    if (openFailure case final failure?) {
      openFailure = null;
      throw failure;
    }
    final collection = _FakeCollection<T>(namespace);
    collections.add(collection as _FakeCollection<Object?>);
    return collection;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopHold?.future;
    if (stopFailure case final failure?) {
      stopFailure = null;
      throw failure;
    }
  }
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

    test('a canonical own sharedBy is kept', () async {
      await session.notify(
          const JsKey('k', sharedWith: '@bob', sharedBy: 'A.LICE'), 'v');

      expect(service.params.last.atKey.sharedBy, '@alice');
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

    test(
        'notify with mismatched sharedBy rejects with bad_key and sends nothing',
        () async {
      await expectLater(
          session.notify(
              const JsKey('k', sharedWith: '@bob', sharedBy: '@carol'), 'v'),
          throwsA(isA<BadKeyException>()));
      expect(service.params, isEmpty);
    });

    test(
        'notify with public or cached flag rejects with bad_key and sends nothing',
        () async {
      await expectLater(
          session.notify(
              const JsKey('k', sharedWith: '@bob', isPublic: true), 'v'),
          throwsA(isA<BadKeyException>()));
      await expectLater(
          session.notify(
              const JsKey('k', sharedWith: '@bob', isCached: true), 'v'),
          throwsA(isA<BadKeyException>()));
      expect(service.params, isEmpty);
    });

    test(
        'notify with empty or invalid key or invalid sharedWith rejects with bad_key and sends nothing',
        () async {
      for (final bad in [
        const JsKey('', sharedWith: '@bob'),
        const JsKey('a:b', sharedWith: '@bob'),
        const JsKey('a@b', sharedWith: '@bob'),
        const JsKey('a b', sharedWith: '@bob'),
        const JsKey('k', sharedWith: '@bob', namespace: ''),
        const JsKey('k', sharedWith: '@bob', namespace: 'a b'),
        const JsKey('k', sharedWith: '@a@b'),
        const JsKey('k', sharedWith: '@bob '),
        const JsKey('k', sharedWith: ''),
      ]) {
        await expectLater(
            session.notify(bad, 'v'), throwsA(isA<BadKeyException>()),
            reason: '${bad.key}/${bad.namespace}/${bad.sharedWith}');
      }
      expect(service.params, isEmpty);
    });

    test('notify interrupted by close rejects with closed', () async {
      service.status = NotificationStatusEnum.undelivered;
      service.exception = AtClientException('AT0001', 'stopped');
      service.hold = Completer<void>();

      final future = session.notify(const JsKey('k', sharedWith: '@bob'), 'v');
      await pumpEventQueue();
      await session.close();
      service.hold!.complete();

      await expectLater(future, throwsA(isA<SessionClosedException>()));
    });

    test('failed notify does not evict sent echo ids', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      for (var i = 0; i < 1024; i++) {
        await session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      }
      // Failed pre-send calls (not sent to secondary) must not enter _sent.
      service
        ..reportsSent = false
        ..status = NotificationStatusEnum.undelivered
        ..exception = AtClientException('AT0001', 'failed');
      for (var i = 0; i < 10; i++) {
        await expectLater(
            session.notify(const JsKey('k', sharedWith: '@alice'), 'v'),
            throwsA(isA<AtClientException>()));
      }

      service.events.add(_echo('n0'));
      await pumpEventQueue();
      expect(received, isEmpty);
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
      final unsubscribe =
          session.subscribe('.*', received.add, onError: (_) {});

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

    test(
        'subscribe drops notifications with malformed keys or wrong sharedWith',
        () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events
        ..add(_event('m1', key: '@alice:k.wavi@bob@eve', from: '@eve'))
        ..add(_event('m2', key: '@bob.wavi', from: '@bobwavi'))
        ..add(_event('m3', key: 'cached:cmd.wavi@eve', from: '@eve'))
        ..add(_event('m4', key: '@victim:cmd.wavi@eve', from: '@eve'))
        ..add(_event('m5', key: '@alice:@victim:cmd.wavi@eve', from: '@eve'))
        ..add(_event('m6', key: 'public:@victim:cmd.wavi@eve', from: '@eve'))
        ..add(_event('m7', key: '@alice:hi@alice', from: '@eve'))
        ..add(_event('m8', key: '@alice:plain_text_injection', from: '@eve'))
        ..add(_event('m9', key: 'cached:@victim:k.wavi@eve', from: '@eve'))
        ..add(_event('m10', key: '@alice:.wavi@bob', from: '@bob'))
        ..add(_event('ok', key: '@A.lice:k.wavi@b.ob', from: '@bob'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['ok']);
    });

    test('subscribe with invalid regex rejects naming regex', () {
      expect(() => session.subscribe('[', (_) {}, onError: (_) {}),
          throwsA(isA<InvalidArgumentException>()));
      expect(service.starts, 0);
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

    test(
        'a notification whose sender is not the key owner is dropped with '
        'a warning naming its id, never its value', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events.add(_event('spoofed', from: '@carol', value: 'secret-v'));
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(warnings.single, contains('spoofed'));
      expect(warnings.single, isNot(contains('secret-v')));
    });

    test('sanitizes control and bidi characters in dropped notification logs',
        () async {
      session.subscribe('.*', (_) {}, onError: (_) {});

      service.events.add(_event('bad\nid\u202e\u061c', from: '@carol'));
      await pumpEventQueue();

      expect(warnings.single, isNot(contains('\n')));
      expect(warnings.single, isNot(contains('\u202e')));
      expect(warnings.single, isNot(contains('\u061c')));
      expect(warnings.single, contains(r'\n'));
      expect(warnings.single, contains(r'\u202e'));
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
      await client.connection
          .report(AtConnectionState.offline(AtConnectionCause.stopped));
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(session.status, 'connected');
    });

    group('network changes', () {
      late StreamController<void> network;
      late AtClientJsSession watching;

      setUp(() async {
        network = StreamController<void>.broadcast();
        watching = AtClientJsSession(client,
            namespace: 'wavi',
            isNavigatorOnline: () => navigatorOnline,
            networkChanges: network.stream);
        await client.connection
            .report(AtConnectionState.offline(AtConnectionCause.unreachable));
        await pumpEventQueue();
      });

      tearDown(() async {
        await watching.close();
        await network.close();
      });

      test('an event re-reads whether the browser is online and reports it',
          () async {
        final seen = <String>[];
        watching.onStatus(seen.add);
        expect(watching.status, 'waiting:server');

        navigatorOnline = false;
        network.add(null);
        await pumpEventQueue();
        network.add(null);
        navigatorOnline = true;
        await pumpEventQueue();

        expect(seen, ['waiting:network', 'waiting:server']);
      });

      test('an event that changes nothing reports nothing', () async {
        final seen = <String>[];
        watching.onStatus(seen.add);

        network.add(null);
        await pumpEventQueue();

        expect(seen, isEmpty);
      });

      test('close stops listening to it', () async {
        final seen = <String>[];
        watching.onStatus(seen.add);
        await watching.close();

        navigatorOnline = false;
        network.add(null);
        await pumpEventQueue();

        expect(seen, isEmpty);
        expect(network.hasListener, isFalse);
      });
    });

    test('onStatus after close throws SessionClosedException', () async {
      await session.close();
      expect(() => session.onStatus((_) {}),
          throwsA(isA<SessionClosedException>()));
    });

    test('onStatus listener error does not skip sibling listeners', () async {
      final seen = <String>[];
      late void Function() offThird;
      session.onStatus((_) => throw StateError('boom'));
      session.onStatus((s) {
        seen.add('second:$s');
        offThird();
      });
      offThird = session.onStatus((s) => seen.add('third:$s'));

      await report(AtConnectionState.online());

      expect(seen, ['second:connected']);
    });
  });

  group('collection', () {
    test('after close throws SessionClosedException', () async {
      await session.close();
      await expectLater(session.collection('todos', type: 'Todo'),
          throwsA(isA<SessionClosedException>()));
    });

    test(
        'qualifies the name with the namespace and rejects a bad expiration '
        'with the adapter code', () async {
      await expectLater(
          session.collection('todos', type: 'Todo', expirationMs: 0),
          throwsA(isA<CollectionException>().having(
              (e) => e.kind, 'kind', CollectionFailure.invalidArgument)));
    });

    test('a name already ending in the namespace is kept', () {
      expect(AtClientJsSession.qualified('todos.wavi', 'wavi'), 'todos.wavi');
      expect(AtClientJsSession.qualified('todos', 'wavi'), 'todos.wavi');
      expect(
          AtClientJsSession.qualified('todos.MyApp', 'MyApp'), 'todos.myapp');
    });

    test(
        'opening a notification-backed collection starts listening on notificationService',
        () async {
      await session.collection('todos', type: 'Todo', eventSource: 'data');
      expect(service.starts, 0);

      await session.collection('todos', type: 'Todo', eventSource: 'notifs');
      expect(service.starts, 1);

      await session.collection('notes', type: 'Note');
      expect(service.starts, 2);
      expect(client.openedCollections.last.$1, 'notes.wavi');
    });

    test('a repeated collection call reuses the one open adapter', () async {
      await session.collection('todos', type: 'Todo');
      await session.collection('todos', type: 'Todo');
      await session.collection('todos.wavi', type: 'Todo');

      expect(client.openedCollections, hasLength(1));
    });

    test('a different type, expiration or event source opens its own',
        () async {
      await session.collection('todos', type: 'Todo');
      await session.collection('todos', type: 'Note');
      await session.collection('todos', type: 'Todo', expirationMs: 1000);
      await session.collection('todos', type: 'Todo', eventSource: 'data');

      expect(client.openedCollections, hasLength(4));
    });

    test('a failed open is not kept, the next call opens again', () async {
      client.openFailure = StateError('boom');
      await expectLater(session.collection('todos', type: 'Todo'),
          throwsA(isA<CollectionException>()));

      await session.collection('todos', type: 'Todo');
      await session.collection('todos', type: 'Todo');

      expect(client.openedCollections, hasLength(2));
    });

    test('rejects invalid collection names and folds mixed-case namespace',
        () async {
      final mixed = AtClientJsSession(client, namespace: 'MyApp');
      await mixed.collection('Todos', type: 'Todo', eventSource: 'data');
      expect(client.openedCollections.last.$1, 'todos.myapp');

      for (final bad in ['', '.wavi', 'todos.', 'a..b', 'a b', 'a@b', 'a:b']) {
        await expectLater(
            mixed.collection(bad, type: 'Todo'),
            throwsA(isA<CollectionException>().having(
                (e) => e.kind, 'kind', CollectionFailure.invalidArgument)),
            reason: bad);
      }
      expect(() => AtClientJsSession(client, namespace: ''),
          throwsA(isA<InvalidArgumentException>()));
      expect(() => AtClientJsSession(client, namespace: 'a.b'),
          throwsA(isA<InvalidArgumentException>()));
    });
  });

  group('session errors', () {
    test('a closed session refuses each call with SessionClosedException',
        () async {
      await session.close();

      final calls = <String, Future<Object?> Function()>{
        'notify': () =>
            session.notify(const JsKey('k', sharedWith: '@bob'), 'v'),
        'subscribe': () async =>
            session.subscribe('.*', (_) {}, onError: (_) {}),
        'onStatus': () async => session.onStatus((_) {}),
        'collection': () => session.collection('todos', type: 'Todo'),
        'otp': session.otp,
        'pendingEnrollments': session.pendingEnrollments,
        'approve': () => session.approve('e1'),
        'deny': () => session.deny('e1'),
      };
      for (final MapEntry(:key, :value) in calls.entries) {
        await expectLater(value, throwsA(isA<SessionClosedException>()),
            reason: key);
      }
    });

    test(
        'the session and the adapter report caller mistakes with a typed exception',
        () async {
      expect(() => AtClientJsSession(client, namespace: 'a.b'),
          throwsA(isA<InvalidArgumentException>()));
      expect(() => session.subscribe('(', (_) {}, onError: (_) {}),
          throwsA(isA<InvalidArgumentException>()));
      await expectLater(
          session.collection('a b', type: 'Todo'),
          throwsA(isA<CollectionException>().having(
              (e) => e.kind, 'kind', CollectionFailure.invalidArgument)));
      expect(() => AtClientJsSession(client, namespace: 'a.b'),
          isNot(throwsArgumentError));
    });
  });

  group('close', () {
    test('stops the client once', () async {
      await session.close();
      await session.close();

      expect(client.stops, 1);
    });

    test('concurrent close awaits the first stop', () async {
      final hold = Completer<void>();
      client.stopHold = hold;
      var firstDone = false;
      var secondDone = false;

      final p1 = session.close().then((_) => firstDone = true);
      final p2 = session.close().then((_) => secondDone = true);
      await pumpEventQueue();
      expect(client.stops, 1);
      expect(firstDone, isFalse);
      expect(secondDone, isFalse);

      hold.complete();
      await Future.wait([p1, p2]);
      expect(firstDone, isTrue);
      expect(secondDone, isTrue);
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

    test('a close whose stop failed can be tried again', () async {
      client.stopFailure = StateError('boom');
      await expectLater(session.close(), throwsA(isA<StateError>()));

      await session.close();
      await session.close();

      expect(client.stops, 2);
    });

    test('cancels every active watch, none twice once cancelled', () async {
      final adapter = await session.collection('todos', type: 'Todo');
      final cancelled = adapter.watch((_) {}, onError: (_) {});
      adapter.watch((_) {}, onError: (_) {});
      adapter.watch((_) {}, onError: (_) {});
      await cancelled();

      await session.close();

      expect(client.collections.single.cancels, 3);
    });

    test('warns, never swallows silently, when a watch fails to cancel',
        () async {
      final adapter = await session.collection('todos', type: 'Todo');
      client.collections.single.cancelFailure = StateError('boom');
      adapter.watch((_) {}, onError: (_) {});
      adapter.watch((_) {}, onError: (_) {});

      await session.close();

      expect(client.collections.single.cancels, 2);
      expect(warnings, [
        'Failed to cancel collection watch on close',
        'Failed to cancel collection watch on close',
      ]);
      expect(client.stops, 1);
    });

    test('stops delivering to subscribers', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      await session.close();
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test(
        'close stops delivering subscription events and errors even if the '
        'stream emits before cancel settles', () async {
      final received = <JsNotification>[];
      final errors = <Object>[];
      Future<void>? closing;
      session.subscribe(
        '.*',
        (event) {
          received.add(event);
          closing ??= session.close();
        },
        onError: errors.add,
      );

      service.events
        ..add(_event('e1'))
        ..add(_event('e2'))
        ..addError(StateError('late'));
      await pumpEventQueue();
      await closing;

      expect(received.map((e) => e.id), ['e1']);
      expect(errors, isEmpty);
    });

    test('subscribe cancels immediately if close occurs during startListening',
        () async {
      var cancelled = false;
      final controller = StreamController<AtNotification>.broadcast(
        onCancel: () => cancelled = true,
      );
      service.customStream = controller.stream;
      Future<void>? closing;
      service.onStartListening = () => closing = session.close();

      final received = <JsNotification>[];
      final errors = <Object>[];
      session.subscribe('.*', received.add, onError: errors.add);
      await pumpEventQueue();
      await closing;

      expect(cancelled, isTrue);
      expect(controller.hasListener, isFalse);
      controller
        ..add(_event('late'))
        ..addError(StateError('late'));
      await pumpEventQueue();
      expect(received, isEmpty);
      expect(errors, isEmpty);
    });
  });
}
