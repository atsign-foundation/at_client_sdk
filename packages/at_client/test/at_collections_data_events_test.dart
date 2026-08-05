// Coverage for AtCollection's [EventSource.data] path —
// CEvent production driven by DataUpdated / DataDeleted events from
// LocalSecondary, mirroring the notification-driven coverage in
// at_collections_test.dart.
//
// Tests use `collectionWithInjectedDataEvents` from the test hooks so
// no live LocalSecondary subscription is needed; we drive events
// through a controllable broadcast stream.
//
// Event-source coverage: this file is the [EventSource.data]
// counterpart to `at_collections_test.dart` (and the related sub /
// query / query_sub files), which exercise the [EventSource.notifs]
// path. Dual-emission semantics under [EventSource.both] are covered
// by `at_collections_events_both_test.dart`.

import 'dart:async';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;
}

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

    test('sync-pulled cached shared keys dispatch with the bare item id',
        () async {
      // Regression: sync-pulled shared keys are constructed via
      // `AtKey.fromString('cached:<self>:<id>.<ns>@<other>')`. AtKey
      // sets metadata.isCached=true on parse and AtKey.toString() then
      // re-emits the `cached:` prefix. The previous parts extractor
      // stripped only `<sharedWith>:` and `<sharedBy>`, leaving
      // `cached:` glued to the id — `parts.first` came out as
      // `cached:idC` and downstream consumers couldn't match. The
      // extractor now strips the `cached:` (and `public:`) wrapper
      // before splitting.
      final c = buildCollection<String>();
      final updates = <CItemUpdated>[];
      final sub = c.updates.listen(updates.add);

      dataEvents.add(DataUpdated(
        AtKey.fromString('cached:$selfAtSignStr:idc.$namespace$bobStr'),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(updates, hasLength(1));
      expect(updates.single.id, 'idc',
          reason: 'item id should be the bare value, not "cached:idc"');
      expect(updates.single.owner, bob);
      await sub.cancel();
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

  // ---------------------------------------------------------------------------
  // #4 — a reader's OWN outgoing read-receipt (written by markReadByMe) comes
  // back as a local DataUpdated. It must NOT fire a CReadReceipt: you can't
  // receipt your own read. An INCOMING receipt (from another atSign) still
  // must. The guard is `parts.from != self`.
  group('#4 — read-receipt self/incoming discrimination', () {
    test("a reader's own outgoing __rr write fires no CReadReceipt", () async {
      final c = buildCollection<String>();
      final receipts = <CReadReceipt>[];
      final sub = c.readReceipts.listen(receipts.add);

      // self=@alice read @bob's item t1 and wrote her own receipt:
      // `@bob:r.__rr.t1.<ns>@alice` (sharedBy = @alice = self).
      dataEvents.add(DataUpdated(
        AtKey.fromString('$bobStr:r.__rr.t1.$namespace$selfAtSignStr'),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(receipts, isEmpty);
      await sub.cancel();
    });

    test('an incoming receipt from another atSign still fires', () async {
      final c = buildCollection<String>();
      final receipts = <CReadReceipt>[];
      final sub = c.readReceipts.listen(receipts.add);

      // @bob read self=@alice's item t1 and posted a receipt; on @alice it
      // lands as `cached:@alice:r.__rr.t1.<ns>@bob` (sharedBy = @bob).
      dataEvents.add(DataUpdated(
        AtKey.fromString('cached:$selfAtSignStr:r.__rr.t1.$namespace$bobStr'),
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(receipts, hasLength(1));
      expect(receipts.single.from, bob);
      expect(receipts.single.id, 't1');
      await sub.cancel();
    });
  });
}
