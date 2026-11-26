import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client_web/src/collections/item_locks.dart';
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/session/at_client_session.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';

class _FakeNotifications extends Fake implements NotificationService {
  final events = StreamController<AtNotification>.broadcast();
  final params = <NotificationParams>[];
  var status = NotificationStatusEnum.delivered;

  /// The failure the result carries, wrapped by
  /// `AtExceptionManager.createException` as the real service wraps it.
  AtException? exception;

  /// When set, `notify` throws it after the send, as the real service's
  /// awaited poll rethrows what reading the final status throws.
  AtException? pollFailure;
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
    final failure = exception;
    final result = NotificationResult()
      ..notificationID = 'n${nextId++}'
      ..notificationStatusEnum = status
      ..atClientException =
          failure == null ? null : AtExceptionManager.createException(failure);
    if (reportsSent) onSentToSecondary?.call(result);
    await hold?.future;
    if (pollFailure case final thrown?) throw thrown;
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

  @override
  final Atsign atSign = '@alice'.toAtsign();

  /// Ids `get` was asked for, in order.
  final gets = <String>[];

  /// When set, `get` waits for it, then throws a StateError.
  Completer<void>? getHold;

  @override
  Future<CItem<T>> get(String id, Atsign owner) async {
    gets.add(id);
    await getHold?.future;
    throw StateError('no item');
  }

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

/// A stream whose subscriptions fail to cancel, by throwing or by a failed
/// future, as [cancel] does.
class _CancelFailingStream extends Stream<AtNotification> {
  _CancelFailingStream(this.cancel);

  final Future<void> Function() cancel;

  @override
  StreamSubscription<AtNotification> listen(
          void Function(AtNotification event)? onData,
          {Function? onError,
          void Function()? onDone,
          bool? cancelOnError}) =>
      _CancelFailingSubscription(cancel);
}

class _CancelFailingSubscription extends Fake
    implements StreamSubscription<AtNotification> {
  _CancelFailingSubscription(this._cancel);

  final Future<void> Function() _cancel;

  @override
  Future<void> cancel() => _cancel();
}

/// A connection whose status subscription fails to cancel.
class _CancelFailingConnection extends Fake implements AtConnection {
  @override
  AtConnectionState get current => AtConnectionState.online();

  @override
  Stream<AtConnectionState> get changes =>
      (StreamController<AtConnectionState>()
            ..onCancel = () => Future<void>.error(StateError('boom')))
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
  AtConnection connection = AtConnection(
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
  late AtClientSession session;
  late _FakeNotifications service;
  late List<String> warnings;
  late bool navigatorOnline;

  setUp(() {
    client = _FakeClient();
    service = client.notificationService;
    warnings = [];
    navigatorOnline = true;
    session = AtClientSession(client,
        namespace: 'wavi',
        warn: warnings.add,
        isNavigatorOnline: () => navigatorOnline);
  });

  group('keys', () {
    // notify is the only call that takes a key until the collections surface
    // lands, so these go through it; each key is complete atKey text, as
    // notify requires (D-44).
    Future<String> sentKey(String key) async {
      await session.notify(key, 'v');
      return service.params.last.atKey.toString();
    }

    test('a shared key is sent as its atKey text', () async {
      expect(await sentKey('@bob:k.wavi@alice'), '@bob:k.wavi@alice');
      expect(service.params.last.atKey.metadata.namespaceAware, isFalse);
    });

    test("notify sends the key text's namespace, not the session's", () async {
      expect(await sentKey('@bob:k.other@alice'), '@bob:k.other@alice');
      expect(await sentKey('@bob:k@alice'), '@bob:k@alice');
      expect(service.params.last.atKey.metadata.namespaceAware, isFalse);
    });

    test('a canonical own sharedBy is kept', () async {
      await session.notify('@bob:k.wavi@A.LICE', 'v');

      expect(service.params.last.atKey.sharedBy, '@alice');
    });

    test('public and cached key text is refused before the parse', () async {
      for (final key in [
        'public:k.wavi@alice',
        'cached:public:k.wavi@alice',
      ]) {
        await expectLater(
            session.notify(key, 'v'), throwsA(isA<InvalidKeyException>()),
            reason: key);
      }
      await expectLater(session.notify('cached:@bob:k.wavi@alice', 'v'),
          throwsA(isA<InvalidKeyException>()));
      expect(service.params, isEmpty);
    });
  });

  group('notify', () {
    test('without sharedWith it is a bad key and sends nothing', () async {
      for (final key in ['', 'k.wavi@alice', '@alice']) {
        await expectLater(
            session.notify(key, 'v'), throwsA(isA<InvalidKeyException>()),
            reason: key);
      }
      expect(service.params, isEmpty);
    });

    test('sends an update on the shared key, outside the app namespace',
        () async {
      final sent = await session.notify('@bob:rpc.tally@alice', 'hi');

      expect(sent, isTrue);
      final params = service.params.single;
      expect(params.atKey.toString(), '@bob:rpc.tally@alice');
      expect(params.atKey.metadata.namespaceAware, isFalse);
      expect(params.operation, OperationEnum.update);
      expect(params.value, 'hi');
    });

    test('resolves false when the notification is not delivered', () async {
      service.status = NotificationStatusEnum.undelivered;

      expect(await session.notify('@bob:k.wavi@alice', 'v'), isFalse);
    });

    test('a send at_client reports failed is a send failure', () async {
      for (final cause in [
        UnAuthorizedException('not authorized'),
        AtKeyException('Key cannot contain @'),
      ]) {
        service
          ..reportsSent = false
          ..status = NotificationStatusEnum.undelivered
          ..exception = cause;

        await expectLater(
            session.notify('@bob:k.wavi@alice', 'v'),
            throwsA(isA<NotifyFailedException>()
                .having((e) => e.kind, 'kind', NotifyFailure.sendFailed)),
            reason: '${cause.runtimeType}');
      }
    });

    test(
        'notify with mismatched sharedBy rejects with bad_key and sends nothing',
        () async {
      await expectLater(session.notify('@bob:k.wavi@carol', 'v'),
          throwsA(isA<InvalidKeyException>()));
      expect(service.params, isEmpty);
    });

    test(
        'notify with public or cached flag rejects with bad_key and sends nothing',
        () async {
      for (final bad in [
        'public:k.wavi@alice',
        'cached:public:k.wavi@alice',
        'cached:@bob:k.wavi@alice',
      ]) {
        await expectLater(
            session.notify(bad, 'v'), throwsA(isA<InvalidKeyException>()),
            reason: bad);
      }
      expect(service.params, isEmpty);
    });

    test(
        'notify with empty or invalid key or invalid sharedWith rejects with bad_key and sends nothing',
        () async {
      for (final bad in [
        '',
        '@bob',
        'k.wavi@alice',
        '@bob:k:x.wavi@alice',
        'not:a:key@alice',
        '@a@b:k.wavi@alice',
        '@bob:k..x.wavi@alice',
        '@bob:k wavi@alice',
        '@bob:k.wavi.@alice',
        'Public:k.wavi@alice',
        'CACHED:k.wavi@alice',
        'LOCAL:k.wavi@alice',
        'bob:k.wavi@alice',
        'privatekey:privatekey',
      ]) {
        await expectLater(
            session.notify(bad, 'v'), throwsA(isA<InvalidKeyException>()),
            reason: bad);
      }
      expect(service.params, isEmpty);
    });

    test(
        'a notify that cannot reach the atServer is an offline failure, or a timeout when it does not answer',
        () async {
      for (final (cause, kind) in [
        (SecondaryConnectException('unable to connect'), NotifyFailure.offline),
        (AtTimeoutException('no response'), NotifyFailure.timeout),
      ]) {
        service
          ..reportsSent = false
          ..status = NotificationStatusEnum.undelivered
          ..exception = cause
          ..pollFailure = cause;

        await expectLater(
            session.notify('@bob:k.wavi@alice', 'v'),
            throwsA(isA<NotifyFailedException>()
                .having((e) => e.kind, 'kind', kind)),
            reason: '${cause.runtimeType}');
      }
    });

    test('a failure where an atServer answered is not an offline failure',
        () async {
      for (final cause in [
        UnAuthorizedException('not authorized'),
        UnAuthenticatedException('not authenticated'),
        HandShakeException('handshake failed'),
        SecondaryNotFoundException('no atServer'),
      ]) {
        service.pollFailure = cause;

        await expectLater(
            session.notify('@bob:k.wavi@alice', 'v'), throwsA(same(cause)),
            reason: '${cause.runtimeType}');
      }
    });

    test('notify interrupted by close rejects with closed', () async {
      service.status = NotificationStatusEnum.undelivered;
      service.exception = AtClientException('AT0001', 'stopped');
      service.hold = Completer<void>();

      final future = session.notify('@alice:k.wavi@alice', 'v');
      await pumpEventQueue();
      await session.close();
      service.hold!.complete();

      await expectLater(future, throwsA(isA<SessionClosedException>()));
    });

    test('failed notify does not evict sent echo ids', () async {
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      for (var i = 0; i < 1024; i++) {
        await session.notify('@alice:k.wavi@alice', 'v');
      }
      // Failed pre-send calls (not sent to secondary) must not enter _sent.
      service
        ..reportsSent = false
        ..status = NotificationStatusEnum.undelivered
        ..exception = AtClientException('AT0001', 'failed');
      for (var i = 0; i < 10; i++) {
        await expectLater(session.notify('@alice:k.wavi@alice', 'v'),
            throwsA(isA<NotifyFailedException>()));
      }

      // Calls that reach the secondary but poll undelivered have no echo
      // coming, so their ids must not evict the live ones either.
      service.reportsSent = true;
      for (var i = 0; i < 10; i++) {
        await expectLater(session.notify('@alice:k.wavi@alice', 'v'),
            throwsA(isA<NotifyFailedException>()));
      }

      service.events.add(_echo('n0'));
      await pumpEventQueue();
      expect(received, isEmpty);
    });

    test('an unknown-status notify still leaves the sent id set bounded',
        () async {
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      for (var i = 0; i < 1024; i++) {
        await session.notify('@alice:k.wavi@alice', 'v');
      }
      // NotificationStatusEnum has no third value, so an exception-carrying
      // undelivered result stands in for an outcome the session cannot call
      // delivered. Its id must be forgotten before the prune: it suppresses
      // neither its own echo nor the oldest live id.
      service
        ..status = NotificationStatusEnum.undelivered
        ..exception = AtClientException('AT0001', 'unknown outcome');
      await expectLater(session.notify('@alice:k.wavi@alice', 'v'),
          throwsA(isA<NotifyFailedException>()));

      service.events
        ..add(_echo('n1024'))
        ..add(_echo('n0'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['n1024']);
    });
  });

  group('subscribe', () {
    test('subscribes decrypted, starts the monitor and delivers events',
        () async {
      final received = <ReceivedNotification>[];

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
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events.add(_event('d1', operation: 'delete'));
      service.events.add(_event('d2', operation: 'update'));
      service.events.add(_event('d3', operation: null));
      await pumpEventQueue();

      expect(received.map((n) => n.operation), ['delete', 'update', 'update']);
    });

    test('unsubscribe stops delivery', () async {
      final received = <ReceivedNotification>[];
      final unsubscribe =
          session.subscribe('.*', received.add, onError: (_) {});

      unsubscribe();
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test('delivers only a notification sent by the key owner', () async {
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      service.events
        ..add(_event('other', from: '@carol'))
        ..add(_event('own', from: '@bob'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['own']);
    });

    test('matches the sender and the key owner by canonical atSign', () async {
      final received = <ReceivedNotification>[];
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
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      await session.notify('@alice:k.wavi@alice', 'v');
      service.events
        ..add(_echo('n0'))
        ..add(_event('other'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['other']);
    });

    test('delivers a peer notification that reuses an id this session sent',
        () async {
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      await session.notify('@alice:k.wavi@alice', 'v');
      service.events
        ..add(_event('n0', key: '@alice:attalk.wavi@bob', from: '@bob'))
        ..add(_echo('n0'));
      await pumpEventQueue();

      expect(received.map((n) => (n.id, n.from)), [('n0', '@bob')]);
    });

    test('drops an echo that arrives before notify resolves', () async {
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});
      service.hold = Completer<void>();
      final pending = session.notify('@alice:k.wavi@alice', 'v');
      await pumpEventQueue();
      service.events.add(_echo('n0'));
      await pumpEventQueue();
      service.hold!.complete();
      await pending;

      expect(received, isEmpty);
    });

    test('remembers only the last 1024 sent ids', () async {
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      for (var i = 0; i < 1025; i++) {
        await session.notify('@alice:k.wavi@alice', 'v');
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
      final received = <ReceivedNotification>[];
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
      expect(
          () => session.subscribe('[', (_) {}, onError: (_) {}),
          throwsA(isA<InvalidArgumentException>()
              .having((e) => e.parameter, 'parameter', 'regex')));
      expect(service.starts, 0);
      expect(service.lastRegex, isNull);
    });

    test('subscribe hands the service the regex it compiled, unchanged', () {
      session.subscribe(r'rpc\.req', (_) {}, onError: (_) {});

      expect(service.lastRegex, r'rpc\.req');
    });
  });

  group('subscribe errors and drops', () {
    test('a stream error reaches onError and the subscription survives',
        () async {
      final received = <ReceivedNotification>[];
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
      final received = <ReceivedNotification>[];
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

      await session.notify('@alice:k.wavi@alice', 'v');
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

    Future<void> expectStatus(
        AtConnectionState state, bool onLine, String status) async {
      navigatorOnline = onLine;
      await report(state);
      expect(session.status, status);
    }

    test('online is connected',
        () => expectStatus(AtConnectionState.online(), true, 'connected'));

    test(
        'unreachable with the browser online is waiting:server',
        () => expectStatus(
            AtConnectionState.offline(AtConnectionCause.unreachable),
            true,
            'waiting:server'));

    test(
        'unreachable with the browser offline is waiting:network',
        () => expectStatus(
            AtConnectionState.offline(AtConnectionCause.unreachable),
            false,
            'waiting:network'));

    test(
        'no atServer is waiting:server',
        () => expectStatus(
            AtConnectionState.offline(AtConnectionCause.noAtServer),
            true,
            'waiting:server'));

    test(
        'revoked is waiting:auth',
        () => expectStatus(AtConnectionState.refused(AtConnectionCause.revoked),
            true, 'waiting:auth'));

    test(
        'unauthenticated is waiting:auth',
        () => expectStatus(
            AtConnectionState.refused(AtConnectionCause.unauthenticated),
            true,
            'waiting:auth'));

    test(
        'enrollment not approved is waiting:auth',
        () => expectStatus(
            AtConnectionState.refused(AtConnectionCause.enrollmentNotApproved),
            true,
            'waiting:auth'));

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
      late AtClientSession watching;

      setUp(() async {
        network = StreamController<void>.broadcast();
        watching = AtClientSession(client,
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
        'collection operations and watch reject with closed after session close',
        () async {
      final todos =
          await session.collection('todos', type: 'Todo', eventSource: 'data');
      await session.close();
      final address = (id: 'i1', owner: Atsign('@alice'));

      for (final (name, call) in <(String, Future<Object?> Function())>[
        ('create', () => todos.create({'a': 1})),
        ('get', () => todos.get(address)),
        ('list', () => todos.list()),
        ('query', () => todos.query(const [])),
        ('update', () => todos.update(address, {'a': 2})),
        ('share', () => todos.share(address, ['@bob'])),
        ('remove', () => todos.remove(address)),
      ]) {
        await expectLater(call(), throwsA(isA<SessionClosedException>()),
            reason: name);
      }
      expect(() => todos.watch((_) {}, onError: (_) {}),
          throwsA(isA<SessionClosedException>()));
    });

    test(
        'qualifies the name with the namespace and rejects a bad expiration '
        'with the adapter code', () async {
      await expectLater(
          session.collection('todos', type: 'Todo', expirationMs: 0),
          throwsA(isA<JsCollectionsError>().having(
              (e) => e.kind, 'kind', CollectionFailure.invalidArgument)));
    });

    test('a name already ending in the namespace is kept', () {
      expect(AtClientSession.qualifiedCollectionName('todos.wavi', 'wavi'),
          'todos.wavi');
      expect(AtClientSession.qualifiedCollectionName('todos', 'wavi'),
          'todos.wavi');
      expect(AtClientSession.qualifiedCollectionName('Todos.MyApp', 'myapp'),
          'todos.myapp');
    });

    test('a collection without an expiration keeps items for seven days',
        () async {
      await session.collection('todos', type: 'Todo');

      expect(client.openedCollections.single.$2, const Duration(days: 7));
    });

    test('an explicit expiration wins over the seven-day default', () async {
      await session.collection('todos', type: 'Todo', expirationMs: 1000);

      expect(client.openedCollections.single.$2,
          const Duration(milliseconds: 1000));
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

    test('a repeated collection call builds a fresh adapter each time',
        () async {
      final first = await session.collection('todos', type: 'Todo');
      final second = await session.collection('todos', type: 'Todo');
      await session.collection('todos.wavi', type: 'Todo');

      expect(identical(first, second), isFalse);
      expect(client.openedCollections, hasLength(3));
    });

    test(
        'two handles with different eventSource and expiration serialise on one namespace, id and owner',
        () async {
      final data = await session.collection('todos',
          type: 'Todo', eventSource: 'data', expirationMs: 1000);
      final notifs = await session.collection('Todos.WAVI',
          type: 'Todo', eventSource: 'notifs', expirationMs: 2000);
      final fake = client.collections.first;
      fake.getHold = Completer<void>();
      final alice = (id: 'I1', owner: '@alice'.toAtsign());
      final same = (id: 'i1', owner: '@alice'.toAtsign());
      final other = (id: 'i2', owner: '@alice'.toAtsign());
      // The second open is a different fake collection; share the probe.
      client.collections.last.getHold = fake.getHold;

      final first = data.remove(alice);
      final second = notifs.remove(same);
      final third = notifs.remove(other);
      await pumpEventQueue();

      expect([...fake.gets, ...client.collections.last.gets], ['I1', 'i2']);

      fake.getHold!.complete();
      await Future.wait([
        first,
        second,
        third
      ].map((f) => f.then<Object?>((_) => null, onError: (Object _) => null)));

      expect(
          [...fake.gets, ...client.collections.last.gets], ['I1', 'i2', 'i1']);
    });

    test('the item lock map is empty once the operations complete', () async {
      final locks = ItemLocks();
      final tracked =
          AtClientSession(client, namespace: 'wavi', itemLocks: locks);
      final todos = await tracked.collection('todos', type: 'Todo');
      final address = (id: 'i1', owner: '@alice'.toAtsign());
      await Future.wait([
        for (var i = 0; i < 3; i++)
          todos
              .remove(address)
              .then<Object?>((_) => null, onError: (Object _) => null),
      ]);

      expect(locks.length, 0);
    });

    test('close clears the item lock map', () async {
      final locks = ItemLocks();
      final tracked =
          AtClientSession(client, namespace: 'wavi', itemLocks: locks);
      final todos = await tracked.collection('todos', type: 'Todo');
      client.collections.last.getHold = Completer<void>();
      final held = todos
          .remove((id: 'i1', owner: '@alice'.toAtsign())).then<Object?>(
              (_) => null,
              onError: (Object _) => null);
      await pumpEventQueue();
      expect(locks.length, 1);

      await tracked.close();
      expect(locks.length, 0);
      client.collections.last.getHold!.complete();
      await held;
    });

    test('a failed open leaves nothing behind, the next call opens again',
        () async {
      client.openFailure = StateError('boom');
      await expectLater(session.collection('todos', type: 'Todo'),
          throwsA(isA<JsCollectionsError>()));

      await session.collection('todos', type: 'Todo');
      await session.collection('todos', type: 'Todo');

      expect(client.openedCollections, hasLength(3));
    });

    test('rejects invalid collection names and folds mixed-case namespace',
        () async {
      final mixed = AtClientSession(client, namespace: 'MyApp');
      await mixed.collection('Todos', type: 'Todo', eventSource: 'data');
      expect(client.openedCollections.last.$1, 'todos.myapp');

      for (final bad in ['', '.wavi', 'todos.', 'a..b', 'a b', 'a@b', 'a:b']) {
        await expectLater(
            mixed.collection(bad, type: 'Todo'),
            throwsA(isA<JsCollectionsError>().having(
                (e) => e.kind, 'kind', CollectionFailure.invalidArgument)),
            reason: bad);
      }
      expect(() => AtClientSession(client, namespace: ''),
          throwsA(isA<InvalidArgumentException>()));
      expect(() => AtClientSession(client, namespace: 'a.b'),
          throwsA(isA<InvalidArgumentException>()));
    });
  });

  group('session errors', () {
    test('a closed session refuses each call with SessionClosedException',
        () async {
      await session.close();

      final calls = <String, Future<Object?> Function()>{
        'notify': () => session.notify('@alice:k.wavi@alice', 'v'),
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
      expect(() => AtClientSession(client, namespace: 'a.b'),
          throwsA(isA<InvalidArgumentException>()));
      expect(() => session.subscribe('(', (_) {}, onError: (_) {}),
          throwsA(isA<InvalidArgumentException>()));
      await expectLater(
          session.collection('a b', type: 'Todo'),
          throwsA(isA<JsCollectionsError>().having(
              (e) => e.kind, 'kind', CollectionFailure.invalidArgument)));
      expect(() => AtClientSession(client, namespace: 'a.b'),
          isNot(throwsArgumentError));
    });
  });

  group('close', () {
    test('the session close awaits the opener stop', () async {
      final gate = Completer<void>();
      var stopped = false;
      final own = AtClientSession(client, namespace: 'app', stop: () async {
        await gate.future;
        stopped = true;
      });
      var closed = false;
      final closing = own.close().then((_) => closed = true);
      await pumpEventQueue();
      expect(closed, isFalse);
      gate.complete();
      await closing;
      expect((stopped, closed, client.stops), (true, true, 0));
    });

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
        () => session.notify('@alice:k.wavi@alice', 'v'),
        () async => session.subscribe('.*', (_) {}, onError: (_) {}),
      ]) {
        await expectLater(call(), throwsA(isA<SessionClosedException>()));
      }
    });

    test('close removes the network listeners even when a stop step fails',
        () async {
      client.connection = _CancelFailingConnection();
      var networkCancelled = false;
      final network = StreamController<void>.broadcast(
          onCancel: () => networkCancelled = true);
      final watching = AtClientSession(client,
          namespace: 'wavi',
          warn: warnings.add,
          networkChanges: network.stream);

      await watching.close();

      expect(networkCancelled, isTrue);
      expect(warnings, ['Failed to cancel status subscription on close']);
      await network.close();
    });

    test('a close whose stop failed returns the same failure when called again',
        () async {
      client.stopFailure = StateError('boom');

      final first = session.close();
      Object? firstError;
      try {
        await first;
        fail('the first close should have failed');
      } on StateError catch (e) {
        firstError = e;
      }

      final second = session.close();
      final third = session.close();
      expect(second, same(first));
      expect(third, same(first));

      for (final later in [second, third]) {
        Object? error;
        try {
          await later;
        } on StateError catch (e) {
          error = e;
        }
        expect(error, same(firstError));
      }
      expect(client.stops, 1);
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
      final received = <ReceivedNotification>[];
      session.subscribe('.*', received.add, onError: (_) {});

      await session.close();
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test(
        'close stops delivering subscription events and errors even if the '
        'stream emits before cancel settles', () async {
      final received = <ReceivedNotification>[];
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

    test('warns when the subscription of a failed start fails to cancel',
        () async {
      service.customStream =
          _CancelFailingStream(() => throw StateError('boom'));
      service.onStartListening = () => throw StateError('start');

      expect(() => session.subscribe('.*', (_) {}, onError: (_) {}),
          throwsA(isA<StateError>()));
      await pumpEventQueue();

      expect(warnings, ['Failed to cancel notification subscription']);
    });

    test('warns when an unsubscribed subscription fails to cancel', () async {
      service.customStream =
          _CancelFailingStream(() => Future.error(StateError('boom')));

      session.subscribe('.*', (_) {}, onError: (_) {})();
      await pumpEventQueue();

      expect(warnings, ['Failed to cancel notification subscription']);
    });

    test('a subscription whose stream completes is removed', () async {
      final subscriptions = <StreamSubscription<Object?>>{};
      final tracked = AtClientSession(client,
          namespace: 'wavi', subscriptions: subscriptions);
      tracked.subscribe('.*', (_) {}, onError: (_) {});
      expect(subscriptions, hasLength(1));

      await service.events.close();
      await pumpEventQueue();

      expect(subscriptions, isEmpty);
      await tracked.close();
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

      final received = <ReceivedNotification>[];
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
