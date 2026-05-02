// Coverage for AtCollection's `eventsFromLocalSecondary: true` path —
// CEvent production driven by DataUpdated / DataDeleted events from
// LocalSecondary, mirroring the notification-driven coverage in
// at_collections_test.dart.
//
// Tests use `collectionWithInjectedDataEvents` from the test hooks so
// no live LocalSecondary subscription is needed; we drive events
// through a controllable broadcast stream.

import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {}

class _FakeAtKey extends Fake implements AtKey {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAtKey());
  });

  late _MockAtClient atClient;
  late StreamController<DataEvent> dataEvents;

  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const bobStr = '@bob';
  final bob = bobStr.toAtsign();
  const namespace = 'tasks.app_1.my_apps';

  setUp(() {
    atClient = _MockAtClient();
    dataEvents = StreamController<DataEvent>.broadcast();
    when(() => atClient.atSign).thenReturn(selfAtSign);
  });

  tearDown(() async {
    await dataEvents.close();
  });

  AtCollection<T> buildCollection<T>({
    String ns = namespace,
    Duration ttl = const Duration(days: 7),
  }) =>
      collectionWithInjectedDataEvents<T>(
        atClient,
        ns,
        ttl,
        dataEvents: dataEvents.stream,
      );

  AtKey objKey({required String id, required String owner, String? to}) =>
      AtKey.fromString(
        to != null ? '$to:$id.$namespace$owner' : '$id.$namespace$owner',
      );

  // ---------------------------------------------------------------------------
  group('L0 direct items', () {
    test('DataUpdated fires CItemUpdated', () async {
      final c = buildCollection<String>();
      final received = <CItemUpdated>[];
      final sub = c.updates.listen(received.add);

      dataEvents.add(DataUpdated(
        objKey(id: 'id9', owner: selfAtSignStr),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.id, 'id9');
      expect(received.single.owner, selfAtSign);
      await sub.cancel();
    });

    test('DataDeleted fires CItemDeleted', () async {
      final c = buildCollection<String>();
      final received = <CItemDeleted>[];
      final sub = c.deletes.listen(received.add);

      dataEvents.add(DataDeleted(
        objKey(id: 'id9', owner: bobStr, to: selfAtSignStr),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.id, 'id9');
      expect(received.single.owner, bob);
      await sub.cancel();
    });

    test('updates and deletes streams are typed-disjoint', () async {
      final c = buildCollection<String>();
      final updates = <CItemUpdated>[];
      final deletes = <CItemDeleted>[];
      final updSub = c.updates.listen(updates.add);
      final delSub = c.deletes.listen(deletes.add);

      dataEvents.add(
        DataUpdated(objKey(id: 'ida', owner: selfAtSignStr)),
      );
      dataEvents.add(
        DataDeleted(objKey(id: 'idb', owner: bobStr, to: selfAtSignStr)),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(updates, hasLength(1));
      expect(updates.single.id, 'ida');
      expect(deletes, hasLength(1));
      expect(deletes.single.id, 'idb');
      await updSub.cancel();
      await delSub.cancel();
    });

    test('unrelated namespaces are filtered out', () async {
      final c = buildCollection<String>();
      final received = <CEvent>[];
      final sub = c.watch().listen(received.add);

      // A key whose namespace doesn't match the collection's regex.
      dataEvents.add(DataUpdated(
        AtKey.fromString('idX.different_ns.app$selfAtSignStr'),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  group('handleDataEventForTest direct entry', () {
    test('routes through the same dispatcher as live subscription', () async {
      final c = buildCollection<String>();
      final received = <CItemUpdated>[];
      final sub = c.updates.listen(received.add);

      await handleDataEventForTest(
        c,
        DataUpdated(objKey(id: 'idz', owner: selfAtSignStr)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.id, 'idz');
      await sub.cancel();
    });
  });
}
