import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _FakeAtKey extends Fake implements AtKey {}

class _MockNotificationService extends Mock implements NotificationService {}

/// Catalogue: features/at_client/collection_public_records.feature
void main() {
  setUpAll(() => registerFallbackValue(_FakeAtKey()));

  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'list.todos';
  const publicRecord = 'cached:public:__nskey.$namespace$bob';

  late _MockAtClient atClient;
  late StreamController<AtNotification> notifications;
  late StreamController<DataEvent> dataEvents;

  /// @alice's local storage, by key, as sync leaves it.
  late Map<String, String> stored;

  String envelope(String obj) => jsonEncode({'type': 'n/a', 'obj': obj});

  Future<AtValue> read(Invocation inv) async {
    final key = (inv.positionalArguments.first as AtKey).toString();
    final value = stored[key];
    if (value == null) throw AtKeyNotFoundException(key);
    return AtValue()
      ..value = value
      ..metadata = (Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().toUtc().add(const Duration(days: 1)));
  }

  setUp(() {
    atClient = _MockAtClient();
    notifications = StreamController<AtNotification>.broadcast();
    dataEvents = StreamController<DataEvent>.broadcast();
    stored = {
      'a1.$namespace$alice': envelope('hers'),
      '$bob:a1.$namespace$alice': envelope('hers'),
      'cached:$alice:b1.$namespace$bob': envelope('shared with her'),
      'public:p1.$namespace$alice': envelope('her own public record'),
    };
    when(() => atClient.atSign).thenReturn(alice.toAtsign());
    when(() => atClient.getAtKeys(regex: any(named: 'regex')))
        .thenAnswer((inv) async {
      final scan = RegExp(inv.namedArguments[#regex] as String);
      return [
        for (final key in stored.keys)
          if (scan.hasMatch(key)) AtKey.fromString(key)
      ];
    });
    when(() => atClient.get(any())).thenAnswer(read);
    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer(read);
  });

  tearDown(() async {
    await notifications.close();
    await dataEvents.close();
  });

  AtNotification notification(String key, String operation) => AtNotification(
      'n-$operation',
      key,
      bob,
      alice,
      DateTime.now().millisecondsSinceEpoch,
      'key',
      false,
      operation: operation);

  test(
      "A peer's public record never becomes an item of a collection that "
      'shares with it', () async {
    final notificationService = _MockNotificationService();
    when(() => notificationService.subscribe(
        regex: any(named: 'regex'),
        shouldDecrypt: any(named: 'shouldDecrypt'))).thenAnswer((inv) {
      final subscribed = RegExp(inv.namedArguments[#regex] as String);
      return notifications.stream.where((n) => subscribed.hasMatch(n.key));
    });
    when(() => atClient.notificationService).thenReturn(notificationService);
    when(() => atClient.dataEvents).thenAnswer((_) => dataEvents.stream);
    final c =
        AtCollection<String>(atClient, namespace, const Duration(days: 7));
    final updates = <CItemUpdated>[];
    final deletes = <CItemDeleted>[];
    final subscriptions = [
      c.updates.listen(updates.add),
      c.deletes.listen(deletes.add),
    ];

    for (final value in [envelope('from the public record'), 'not JSON']) {
      stored[publicRecord] = value;
      expect((await c.getItems()).map((i) => '${i.owner}:${i.id}'),
          unorderedEquals(['$alice:a1', '$bob:b1']),
          reason: 'the items are those @alice wrote and the share addressed '
              'to her, whatever the public record holds');
    }

    final record = AtKey.fromString(publicRecord);
    dataEvents
      ..add(DataUpdated(record))
      ..add(DataDeleted(record));
    notifications
      ..add(notification('public:__nskey.$namespace$bob', 'update'))
      ..add(notification('public:__nskey.$namespace$bob', 'delete'));
    dataEvents
        .add(DataUpdated(AtKey.fromString('cached:$alice:b1.$namespace$bob')));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(updates.map((e) => '${e.owner}:${e.id}'), ['$bob:b1'],
        reason: 'the share addressed to her is announced, and the public '
            'record is not');
    expect(deletes, isEmpty);
    for (final s in subscriptions) {
      await s.cancel();
    }
  });

  test(
      'Given a collection that subscribes to notifications, when it '
      'subscribes, then what it asks for admits a share and no public record',
      () async {
    final notificationService = _MockNotificationService();
    String? asked;
    when(() => notificationService.subscribe(
        regex: any(named: 'regex'),
        shouldDecrypt: any(named: 'shouldDecrypt'))).thenAnswer((inv) {
      asked = inv.namedArguments[#regex] as String?;
      return const Stream<AtNotification>.empty();
    });
    when(() => atClient.notificationService).thenReturn(notificationService);

    AtCollection<String>(atClient, namespace, const Duration(days: 7),
        eventSource: EventSource.notifs);

    final subscribed = RegExp(asked!);
    expect(subscribed.hasMatch('$alice:b1.$namespace$bob'), isTrue,
        reason: 'the control: a share addressed to her is asked for');
    for (final key in [
      'public:__nskey.$namespace$bob',
      'cached:public:__nskey.$namespace$bob',
      'public:p1.$namespace$alice',
    ]) {
      expect(subscribed.hasMatch(key), isFalse, reason: key);
    }
  });
}
