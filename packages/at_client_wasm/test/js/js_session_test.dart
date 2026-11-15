import 'dart:async';
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/response/response.dart' show AtResponse;
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
  final store = <String, dynamic>{};
  final metadata = <String, Metadata>{};
  AtKey? lastKey;
  String? lastScanRegex;
  var scanned = <String>[];
  var stops = 0;

  @override
  final _FakeNotifications notificationService = _FakeNotifications();

  @override
  String? getCurrentAtSign() => '@alice';

  @override
  Future<bool> put(AtKey key, dynamic value,
      {PutRequestOptions? putRequestOptions}) async {
    lastKey = key;
    store[key.toString()] = value;
    metadata[key.toString()] = Metadata()..isBinary = false;
    return true;
  }

  @override
  Future<AtResponse> putBinary(AtKey atKey, List<int> value,
      {PutRequestOptions? putRequestOptions}) async {
    lastKey = atKey;
    store[atKey.toString()] = Base2e15.encode(value);
    metadata[atKey.toString()] = Metadata()..isBinary = true;
    return AtResponse()..response = 'ok';
  }

  @override
  Future<AtValue> get(AtKey key, {GetRequestOptions? getRequestOptions}) async {
    lastKey = key;
    if (key.key == 'error') throw StateError('boom');
    // AtClientImpl.get hands a missing key back as this, not as the
    // KeyNotFoundException the secondary raised.
    if (key.key == 'wrapped') throw AtKeyNotFoundException('wrapped not found');
    if (!store.containsKey(key.toString())) {
      throw KeyNotFoundException('${key.key} not found');
    }
    return AtValue()
      ..value = store[key.toString()]
      ..metadata = metadata[key.toString()];
  }

  @override
  Future<bool> delete(AtKey key,
      {DeleteRequestOptions? deleteRequestOptions}) async {
    lastKey = key;
    store.remove(key.toString());
    return true;
  }

  @override
  Future<List<String>> getKeys(
      {String? regex,
      String? sharedBy,
      String? sharedWith,
      bool showHiddenKeys = false,
      bool? useRemoteAtServer}) async {
    lastScanRegex = regex;
    return scanned;
  }

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

void main() {
  late _FakeClient client;
  late AtClientJsSession session;
  late _FakeNotifications service;

  setUp(() {
    client = _FakeClient();
    service = client.notificationService;
    session = AtClientJsSession(client, namespace: 'wavi');
  });

  group('keys', () {
    test('a self key is <key>.<namespace> shared by the own atSign', () async {
      await session.put(const JsKey('k'), 'v');

      final key = client.lastKey!;
      expect(key.toString(), 'k.wavi@alice');
      expect(key.sharedWith, isNull);
      expect(key.metadata.namespaceAware, isFalse);
    });

    test('a given namespace replaces the default', () async {
      await session.put(const JsKey('k', namespace: 'other'), 'v');

      expect(client.lastKey!.toString(), 'k.other@alice');
    });

    test(
        'sharedWith makes a shared key and sharedBy defaults to the own atSign',
        () async {
      await session.put(const JsKey('k', sharedWith: '@bob'), 'v');

      expect(client.lastKey!.toString(), '@bob:k.wavi@alice');
    });

    test('an explicit sharedBy is kept', () async {
      await session.get(const JsKey('k', sharedBy: '@bob'));

      expect(client.lastKey!.sharedBy, '@bob');
    });

    test('an atSign without @ is put in @name form', () async {
      await session.put(const JsKey('k', sharedWith: 'bob'), 'v');

      expect(client.lastKey!.sharedWith, '@bob');
    });
  });

  group('put and get', () {
    test('a string round-trips', () async {
      await session.put(const JsKey('k'), 'v');

      expect(await session.get(const JsKey('k')), 'v');
    });

    test('bytes go to putBinary and come back as bytes', () async {
      final bytes = Uint8List.fromList([0, 1, 2, 250, 255]);
      await session.put(const JsKey('b'), bytes);

      expect(client.metadata['b.wavi@alice']!.isBinary, isTrue);
      final back = await session.get(const JsKey('b'));
      expect(back, isA<Uint8List>());
      expect(back, bytes);
    });

    test('a value that is neither string nor bytes is refused', () async {
      await expectLater(
          session.put(const JsKey('k'), 42), throwsA(isA<ArgumentError>()));
      expect(client.store, isEmpty);
    });

    test('get on a missing key is null', () async {
      expect(await session.get(const JsKey('missing')), isNull);
    });

    test('get on a key at_client reports as AtKeyNotFoundException is null',
        () async {
      expect(await session.get(const JsKey('wrapped')), isNull);
    });

    test('get propagates every other failure', () async {
      await expectLater(
          session.get(const JsKey('error')), throwsA(isA<StateError>()));
    });

    test('delete removes the key', () async {
      await session.put(const JsKey('k'), 'v');
      await session.delete(const JsKey('k'));

      expect(await session.get(const JsKey('k')), isNull);
    });
  });

  group('keys scan', () {
    test('defaults to the namespace', () async {
      await session.keys();

      expect(client.lastScanRegex, r'\.wavi@');
    });

    test('escapes a namespace with regex metacharacters', () async {
      session = AtClientJsSession(client, namespace: 'a.b');
      await session.keys();

      expect(client.lastScanRegex, r'\.a\.b@');
    });

    test('takes a regex over the full key string as given', () async {
      await session.keys(r'^rpc\.');

      expect(client.lastScanRegex, r'^rpc\.');
    });

    test('returns the full key strings', () async {
      client.scanned = ['a.wavi@alice', '@bob:b.wavi@alice'];

      expect(await session.keys(), ['a.wavi@alice', '@bob:b.wavi@alice']);
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

      session.subscribe(r'attalk\.wavi@', received.add);

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
      session.subscribe('.*', received.add);

      service.events.add(_event('d1', operation: 'delete'));
      service.events.add(_event('d2', operation: 'update'));
      service.events.add(_event('d3', operation: null));
      await pumpEventQueue();

      expect(received.map((n) => n.operation), ['delete', 'update', 'update']);
    });

    test('unsubscribe stops delivery', () async {
      final received = <JsNotification>[];
      final unsubscribe = session.subscribe('.*', received.add);

      unsubscribe();
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test('delivers only a notification sent by the key owner', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add);

      service.events
        ..add(_event('other', from: '@carol'))
        ..add(_event('own', from: '@bob'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['own']);
    });

    test('matches the sender and the key owner by canonical atSign', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add);

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
      session.subscribe('.*', received.add);

      await session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      service.events
        ..add(_event('n0'))
        ..add(_event('other'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['other']);
    });

    test('drops an echo that arrives before notify resolves', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add);
      service.hold = Completer<void>();
      final pending =
          session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      await pumpEventQueue();
      service.events.add(_event('n0'));
      await pumpEventQueue();
      service.hold!.complete();
      await pending;

      expect(received, isEmpty);
    });

    test('remembers only the last 1024 sent ids', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add);

      for (var i = 0; i < 1025; i++) {
        await session.notify(const JsKey('k', sharedWith: '@alice'), 'v');
      }
      service.events
        ..add(_event('n0'))
        ..add(_event('n1'))
        ..add(_event('n1024'));
      await pumpEventQueue();

      expect(received.map((n) => n.id), ['n0']);
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
        () => session.put(const JsKey('k'), 'v'),
        () => session.get(const JsKey('k')),
        () => session.delete(const JsKey('k')),
        () => session.keys(),
        () => session.notify(const JsKey('k', sharedWith: '@bob'), 'v'),
        () async => session.subscribe('.*', (_) {}),
      ]) {
        await expectLater(call(), throwsA(isA<SessionClosedException>()));
      }
    });

    test('stops delivering to subscribers', () async {
      final received = <JsNotification>[];
      session.subscribe('.*', received.add);

      await session.close();
      service.events.add(_event('e1'));
      await pumpEventQueue();

      expect(received, isEmpty);
    });
  });
}
