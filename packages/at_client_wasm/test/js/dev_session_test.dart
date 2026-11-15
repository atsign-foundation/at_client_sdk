import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';
import 'package:test/fake.dart';
import 'package:at_client_wasm/src/js/dev_session.dart';

class _FakeNotifications extends Fake implements NotificationService {
  final events = StreamController<AtNotification>.broadcast();
  NotificationParams? lastParams;
  var status = NotificationStatusEnum.delivered;
  AtClientException? exception;
  String? lastRegex;
  bool? lastShouldDecrypt;
  var starts = 0;

  @override
  Future<NotificationResult> notify(NotificationParams notificationParams,
      {bool waitForFinalDeliveryStatus = true,
      bool checkForFinalDeliveryStatus = true,
      bool encryptValue = true,
      Function(NotificationResult)? onSuccess,
      Function(NotificationResult)? onError,
      Function(NotificationResult)? onSentToSecondary}) async {
    lastParams = notificationParams;
    return NotificationResult()
      ..notificationID = 'n1'
      ..notificationStatusEnum = status
      ..atClientException = exception;
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
  final Map<String, dynamic> store = {};
  AtKey? lastPutKey;
  var stops = 0;
  final statusQueries = <String>[];
  var rawStatus = 'data:expired';

  @override
  final _FakeNotifications notificationService = _FakeNotifications();

  @override
  String? getCurrentAtSign() => '@alice';

  @override
  Future<bool> put(AtKey key, dynamic value,
      {bool isDedicated = false, PutRequestOptions? putRequestOptions}) async {
    lastPutKey = key;
    store[key.toString()] = value;
    return true;
  }

  @override
  Future<AtValue> get(AtKey key,
      {bool isDedicated = false, GetRequestOptions? getRequestOptions}) async {
    if (key.key == 'missing') {
      throw KeyNotFoundException('missing');
    }
    if (key.key == 'error') {
      throw StateError('boom');
    }
    return AtValue()..value = store[key.toString()];
  }

  @override
  Future<bool> delete(AtKey key,
      {bool isDedicated = false,
      DeleteRequestOptions? deleteRequestOptions}) async {
    store.remove(key.toString());
    return true;
  }

  @override
  Future<String> notifyStatus(String notificationId) async {
    statusQueries.add(notificationId);
    return rawStatus;
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  group('AtClientDevSession', () {
    test('T7: put constructs correct AtKey', () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      await session.put('k', 'v');

      final key = fake.lastPutKey!;
      expect(key.key, 'k');
      expect(key.namespace, 'myapp');
      expect(key.sharedBy, '@alice');
      expect(key.sharedWith, isNull);
      expect(key.metadata.isPublic, isFalse);
    });

    test('T8: get handles KeyNotFoundException and propagates others',
        () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      final missing = await session.get('missing');
      expect(missing, isNull);

      expect(() => session.get('error'), throwsA(isA<StateError>()));
    });

    test('close stops the client once', () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      await session.close();
      await session.close();

      expect(fake.stops, 1);
    });

    test('T3: notify sends an encrypted update on the shared key', () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      await session.notify('@bob', 'attalk', 'ai6bh', 'hi',
          expiry: Duration(seconds: 5));

      final params = fake.notificationService.lastParams!;
      expect(params.atKey.toString(), '@bob:attalk.ai6bh@alice');
      expect(params.operation, OperationEnum.update);
      expect(params.value, 'hi');
      expect(params.notificationExpiry, Duration(seconds: 5));
    });

    // at_client folds a namespace-aware key into the preference namespace
    // (attalk.ai6bh -> attalk.ai6bh.<app>), which a peer subscribed to
    // attalk\.ai6bh@ never matches; the caller's namespace must go out as is.
    test('T3: notify opts the shared key out of the app namespace', () async {
      final fake = _FakeClient();
      final session = AtClientDevSession(fake, app: 'myapp');

      await session.notify('@bob', 'attalk', 'ai6bh', 'hi');

      expect(fake.notificationService.lastParams!.atKey.metadata.namespaceAware,
          isFalse);
    });

    test('T3: notify throws when the notification is not delivered', () async {
      final fake = _FakeClient();
      fake.notificationService.status = NotificationStatusEnum.undelivered;
      final session = AtClientDevSession(fake, app: 'myapp');

      expect(() => session.notify('@bob', 'attalk', 'ai6bh', 'hi'),
          throwsA(anything));
    });

    // at_client maps a final status of expired, errored or error:… to
    // undelivered with no exception, so the session names the raw status.
    test('T3: an undelivered notify with no exception names the raw status',
        () async {
      final fake = _FakeClient()..rawStatus = 'data:expired';
      fake.notificationService.status = NotificationStatusEnum.undelivered;
      final session = AtClientDevSession(fake, app: 'myapp');

      await expectLater(
          session.notify('@bob', 'attalk', 'ai6bh', 'hi'),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              allOf(contains('n1'), contains('data:expired')))));
      expect(fake.statusQueries, ['n1']);
    });

    test('T3: an undelivered notify rethrows its exception unqueried',
        () async {
      final fake = _FakeClient();
      final cause = AtClientException('AT0001', 'Unable to connect');
      fake.notificationService
        ..status = NotificationStatusEnum.undelivered
        ..exception = cause;
      final session = AtClientDevSession(fake, app: 'myapp');

      await expectLater(session.notify('@bob', 'attalk', 'ai6bh', 'hi'),
          throwsA(same(cause)));
      expect(fake.statusQueries, isEmpty);
    });

    test(
        'T4: onNotification subscribes decrypted, starts the monitor, '
        'and stops delivering after unsubscribe', () async {
      final fake = _FakeClient();
      final service = fake.notificationService;
      final session = AtClientDevSession(fake, app: 'myapp');
      final received = <DevNotification>[];

      final unsubscribe =
          session.onNotification(r'attalk\.ai6bh@', received.add);

      expect(service.lastRegex, r'attalk\.ai6bh@');
      expect(service.lastShouldDecrypt, isTrue);
      expect(service.starts, 1);

      service.events.add(AtNotification(
          'n1', '@alice:attalk.ai6bh@bob', '@bob', '@alice', 42, 'key', true,
          value: 'yo'));
      await pumpEventQueue();
      expect(received.single, (
        from: '@bob',
        key: '@alice:attalk.ai6bh@bob',
        value: 'yo',
        epochMillis: 42
      ));

      unsubscribe();
      service.events.add(AtNotification(
          'n2', '@alice:attalk.ai6bh@bob', '@bob', '@alice', 43, 'key', true,
          value: 'late'));
      await pumpEventQueue();
      expect(received, hasLength(1));
    });
  });
}
