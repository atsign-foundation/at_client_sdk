// Baseline tests for AtCollection<T> as it stands today. These are the
// regression guard for any AtCollection refactor (e.g. sub-collection
// support). Every test here must stay green after subsequent changes.
//
// Focus: behaviour observable through AtCollection's public (and
// @visibleForTesting) API, with atClient stubbed via mocktail. No live
// atServer, no Hive — we only assert that AtCollection drives AtClient
// correctly given the contract of AtClient's interface.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class MockNotificationService extends Mock implements NotificationService {}

class FakeAtKey extends Fake implements AtKey {}

/// Simple domain object used for factory/rehydrate tests.
class Widget {
  final String name;
  Widget(this.name);
  Map<String, dynamic> toJson() => {'name': name};
  factory Widget.fromJson(Map<String, dynamic> json) => Widget(json['name']);
  @override
  bool operator ==(Object other) => other is Widget && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
  });

  // Shared setUp builds a fresh MockAtClient + NotificationService for each
  // test, and stubs the minimum surface the AtCollection constructor needs
  // so we can instantiate without surprises.
  late MockAtClient atClient;
  late MockNotificationService notifications;
  late StreamController<AtNotification> notifStream;
  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const bobStr = '@bob';
  final bob = bobStr.toAtsign();
  const namespace = 'tasks.app_1.my_apps';

  setUp(() {
    atClient = MockAtClient();
    notifications = MockNotificationService();
    notifStream = StreamController<AtNotification>.broadcast();

    when(() => atClient.atSign).thenReturn(selfAtSign);
    when(() => atClient.notificationService).thenReturn(notifications);
    when(
      () => notifications.subscribe(
        regex: any(named: 'regex'),
        shouldDecrypt: any(named: 'shouldDecrypt'),
      ),
    ).thenAnswer((_) => notifStream.stream);
  });

  tearDown(() async {
    await notifStream.close();
  });

  AtCollection<T> buildCollection<T>({
    String ns = namespace,
    Duration ttl = const Duration(days: 7),
  }) {
    return AtCollection<T>(atClient, ns, ttl);
  }

  // ---------------------------------------------------------------------------
  group('construction', () {
    test('rejects a namespace without a dot', () {
      expect(
        () => AtCollection<String>(
            atClient, 'notqualified', const Duration(days: 1)),
        throwsArgumentError,
      );
    });

    test('subscribes to notifications with namespace-scoped regex', () {
      buildCollection<String>();
      verify(
        () => notifications.subscribe(
          regex: '.*\\.$namespace@',
          shouldDecrypt: true,
        ),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  group('create', () {
    test('assigns owner=self, auto id, timestamps, empty sharedWith/readBy',
        () {
      final c = buildCollection<String>(ttl: const Duration(hours: 1));
      final before = DateTime.now().toUtc();
      final item = c.create(obj: 'hello');
      final after = DateTime.now().toUtc();

      expect(item.owner, selfAtSign);
      expect(int.tryParse(item.id), isNotNull,
          reason: 'id is a microsecond timestamp');
      expect(item.obj, 'hello');
      expect(item.sharedWith, isEmpty);
      expect(item.readBy, isEmpty);
      expect(
        item.createdAt.millisecondsSinceEpoch,
        inInclusiveRange(
          before.millisecondsSinceEpoch,
          after.millisecondsSinceEpoch,
        ),
      );
      final expectedExpiry = item.createdAt.add(const Duration(hours: 1));
      expect(item.expiresAt, expectedExpiry);
      expect(item.availableAt, isNull);
    });

    test('honours supplied id and sharedWith', () {
      final c = buildCollection<String>();
      final item = c.create(obj: 'x', id: 'fixed-123', sharedWith: {bob});
      expect(item.id, 'fixed-123');
      expect(item.sharedWith, {bob});
    });

    test('throws when type is supplied but no factory is registered', () {
      final c = buildCollection<String>();
      expect(
        () => c.create(type: 'NotRegistered', obj: 'x'),
        throwsA(isA<StateError>()),
      );
    });

    test('auto-tags Uint8List as binary when type is not supplied', () {
      final c = buildCollection<Uint8List>();
      final item = c.create(obj: Uint8List.fromList([1, 2, 3]));
      expect(item.type, 'binary');
    });

    test('non-Uint8List with no type gets literal n/a', () {
      final c = buildCollection<String>();
      final item = c.create(obj: 'x');
      expect(item.type, 'n/a');
    });
  });

  // ---------------------------------------------------------------------------
  group('factory registry + rehydration (static, shared across collections)',
      () {
    test('registerFactory is used to rehydrate on create+toJson round-trip',
        () {
      AtCollection.registerFactory(type: 'Widget', factory: Widget.fromJson);

      final c = buildCollection<Widget>();
      final item = c.create(type: 'Widget', obj: Widget('w1'));
      expect(item.type, 'Widget');

      // Serialised form mirrors what AtCollection.put writes to atClient.
      final encoded = jsonEncode(item.toJson());
      final decoded = jsonDecode(encoded);
      expect(decoded['type'], 'Widget');
      // The inner 'obj' field survives as JSON; fromJson should reconstruct.
      expect(Widget.fromJson(decoded['obj']), Widget('w1'));
    });

    test('binary type round-trips through Base2e15', () {
      final raw = Uint8List.fromList([0, 127, 255, 10, 42]);
      final c = buildCollection<Uint8List>();
      final item = c.create(obj: raw);
      final encoded = jsonEncode(item.toJson());
      final decoded = jsonDecode(encoded);
      expect(decoded['type'], 'binary');
      expect(Base2e15.decode(decoded['obj']), raw);
    });
  });

  // ---------------------------------------------------------------------------
  group('put — self copy only (no sharedWith)', () {
    setUp(() {
      // No prior self copy: atClient.get() throws; put succeeds.
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
    });

    test('writes a single self key <id>.<ns>@<self>', () async {
      final c = buildCollection<String>();
      final item = c.create(obj: 'hello', id: 'abc');
      final results = await c.put(item);

      expect(results, hasLength(1));
      expect(results.single, isA<OpSuccess>());
      expect(results.single.op, CollectionOp.put);
      expect(results.single.atKey.toString(), 'abc.$namespace$selfAtSignStr');

      final captured = verify(
        () => atClient.put(captureAny(), captureAny()),
      ).captured;
      final key = captured[0] as AtKey;
      final value = captured[1] as String;
      expect(key.toString(), 'abc.$namespace$selfAtSignStr');
      // metadata propagation
      expect(key.metadata.ttr, -1);
      expect(key.metadata.ccd, true);
      expect(key.metadata.ttl, isNotNull);
      expect(key.metadata.expiresAt, isNotNull);
      // value is JSON with type and obj
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      expect(decoded['type'], 'n/a');
      expect(decoded['obj'], 'hello');
      expect(decoded['readBy'], isEmpty);
    });

    test('rejects put for items owned by another atSign', () async {
      // Create the item as alice, then hand it to a second collection whose
      // atSign we rewire to bob, to simulate "someone else's item".
      final aliceColl = buildCollection<String>();
      final item = aliceColl.create(obj: 'hi');

      when(() => atClient.atSign).thenReturn(bob);
      final bobColl = buildCollection<String>();

      await expectLater(bobColl.put(item), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  group('put — shared copies', () {
    setUp(() {
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(() => atClient.delete(any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
    });

    test('writes one recipient copy per entry in sharedWith plus the self copy',
        () async {
      final c = buildCollection<String>();
      final item = c.create(
        obj: 'hi',
        id: 'msg1',
        sharedWith: {bob, '@carol'.toAtsign()},
      );
      final results = await c.put(item);

      // 3 successful puts: self + 2 recipients.
      expect(results.whereType<OpSuccess>().length, 3);
      final writtenKeys = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(
          writtenKeys,
          containsAll([
            'msg1.$namespace$selfAtSignStr',
            '$bobStr:msg1.$namespace$selfAtSignStr',
            '@carol:msg1.$namespace$selfAtSignStr',
          ]));
    });

    test(
        'unshareWithOthers=true only deletes recipients no longer in '
        'sharedWith; retained recipients are updated in place', () async {
      // Diff semantics: put() should delete ONLY the recipient copies for
      // atSigns that are no longer in item.sharedWith. Recipients who are in
      // both the existing set and item.sharedWith are updated (overwritten)
      // by the regular put loop — never delete-then-write.
      final existingBob =
          AtKey.fromString('$bobStr:msg2.$namespace$selfAtSignStr');
      final existingDave =
          AtKey.fromString('@dave:msg2.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [existingBob, existingDave]);

      final c = buildCollection<String>();
      final item = c.create(obj: 'x', id: 'msg2', sharedWith: {bob});
      await c.put(item);

      final deleted = verify(
        () => atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      // @dave lost access → deleted.
      expect(deleted, contains('@dave:msg2.$namespace$selfAtSignStr'));
      // @bob is still a recipient → must NOT be deleted.
      expect(deleted, isNot(contains('$bobStr:msg2.$namespace$selfAtSignStr')));

      // Writes: self + @bob update. @dave never re-written.
      final written = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(written, contains('msg2.$namespace$selfAtSignStr'));
      expect(written, contains('$bobStr:msg2.$namespace$selfAtSignStr'));
      expect(
        written,
        isNot(contains('@dave:msg2.$namespace$selfAtSignStr')),
      );
    });

    test('unshareWithOthers=false preserves unmentioned recipients', () async {
      final existingDave =
          AtKey.fromString('@dave:msg3.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [existingDave]);

      final c = buildCollection<String>();
      final item = c.create(obj: 'x', id: 'msg3', sharedWith: {bob});
      await c.put(item, unshareWithOthers: false);

      verifyNever(() => atClient.delete(any()));
    });

    test('availableAt override propagates to metadata (ttb)', () async {
      final c = buildCollection<String>();
      final item = c.create(obj: 'x', id: 'msg4');
      final future = DateTime.now().add(const Duration(hours: 1));
      await c.put(item, availableAt: future);

      final key = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.first as AtKey;
      expect(key.metadata.availableAt, future);
      expect(key.metadata.ttb, isNotNull);
      expect(key.metadata.ttb, greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  group('getItems / getItemsList / get', () {
    AtValue atValueFor(String id, Object obj, {String type = 'n/a'}) {
      final v = AtValue();
      v.value = jsonEncode({
        'type': type,
        'readBy': <String>[],
        'obj': obj,
      });
      v.metadata = Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().add(const Duration(days: 1));
      return v;
    }

    test('deduplicates keys by fullKeyAndOwner and unions sharedWith',
        () async {
      final selfKey = AtKey.fromString('id1.$namespace$selfAtSignStr');
      final shareBob = AtKey.fromString('$bobStr:id1.$namespace$selfAtSignStr');
      final shareCarol =
          AtKey.fromString('@carol:id1.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey, shareBob, shareCarol]);
      when(() => atClient.get(any()))
          .thenAnswer((_) async => atValueFor('id1', 'hello'));

      final c = buildCollection<String>();
      final response = await c.getItems();
      expect(response.exceptions, isEmpty);
      expect(response.items, hasLength(1));
      final only = response.items.first;
      expect(only.id, 'id1');
      expect(only.owner, selfAtSign);
      expect(only.sharedWith, containsAll([bob, '@carol'.toAtsign()]));
      expect(only.obj, 'hello');
    });

    test('getItemsList throws when any exception accumulates', () async {
      final selfKey = AtKey.fromString('id2.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenThrow(Exception('boom'));

      final c = buildCollection<String>();
      await expectLater(c.getItemsList(), throwsA(isA<Exception>()));

      // But getItems() returns the exception inside the response, not raised.
      final resp = await c.getItems();
      expect(resp.exceptions, hasLength(1));
      expect(resp.items, isEmpty);
    });

    test('get(id, owner) returns a single item or throws when missing',
        () async {
      final selfKey = AtKey.fromString('id3.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any()))
          .thenAnswer((_) async => atValueFor('id3', 'v3'));

      final c = buildCollection<String>();
      final item = await c.get('id3', selfAtSign);
      expect(item.id, 'id3');
      expect(item.obj, 'v3');

      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
      await expectLater(
        c.get('missing', selfAtSign),
        throwsA(isA<AtKeyNotFoundException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('getKeys', () {
    test('composes regex with id and owner filters', () async {
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);

      final c = buildCollection<String>();
      await c.getKeys(id: 'abc', owner: selfAtSign);
      verify(
        () => atClient.getAtKeys(regex: '(^|:)abc\\.$namespace$selfAtSignStr'),
      ).called(1);
    });

    test('defaults id and owner to wildcards', () async {
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);

      final c = buildCollection<String>();
      await c.getKeys();
      verify(
        () => atClient.getAtKeys(regex: '(^|:)[^.]+\\.$namespace@'),
      ).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  group('delete', () {
    setUp(() {
      when(() => atClient.delete(any())).thenAnswer((_) async => true);
    });

    test('rejects items owned by another atSign', () async {
      final aliceColl = buildCollection<String>();
      final item = aliceColl.create(obj: 'x');
      when(() => atClient.atSign).thenReturn(bob);
      final bobColl = buildCollection<String>();
      await expectLater(bobColl.delete(item), throwsArgumentError);
    });

    test('deletes self + shared keys for the item', () async {
      final selfKey = AtKey.fromString('delme.$namespace$selfAtSignStr');
      final shareKey =
          AtKey.fromString('$bobStr:delme.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey, shareKey]);

      final c = buildCollection<String>();
      final item = c.create(obj: 'x', id: 'delme', sharedWith: {bob});
      final results = await c.delete(item);

      final deleted = verify(
        () => atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(
          deleted,
          containsAll([
            'delme.$namespace$selfAtSignStr',
            '$bobStr:delme.$namespace$selfAtSignStr',
          ]));
      expect(results.whereType<OpSuccess>().length, 2);
    });

    test('current behaviour: no descendants scan — descendants are left intact',
        () async {
      // Today delete() only scans for keys sharing the same id at this
      // namespace level. A sub-collection item keyed
      // `<subId>.comments.<parentId>.<parentNs>@<owner>` lives at a DIFFERENT
      // namespace ('<parentId>.comments.<parentNs>') and is not matched by
      // getKeys(id: parentId, owner: self) on the parent collection — so
      // the parent's delete leaves descendants untouched. This test pins
      // that fact in place until the sub-collection refactor changes it.
      final selfKey = AtKey.fromString('p1.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);

      final c = buildCollection<String>();
      final item = c.create(obj: 'x', id: 'p1');
      await c.delete(item);

      final deleted = verify(
        () => atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(deleted, ['p1.$namespace$selfAtSignStr']);
      // No descendant scan was performed — the regex called was the plain
      // parent regex, nothing like '.*\\.p1\\.$namespace@'.
      final regexes = verify(
        () => atClient.getAtKeys(regex: captureAny(named: 'regex')),
      ).captured.cast<String>();
      expect(
        regexes.every((r) => !r.contains('.+\\.p1\\.$namespace')),
        isTrue,
        reason: 'Today delete() does not scan for descendants.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('events — via handleNotification directly', () {
    AtNotification objNotif({
      required String key,
      required String from,
      required String to,
      required String operation,
    }) {
      return AtNotification(
        'nid-1',
        key,
        from,
        to,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: operation,
      );
    }

    test('CItemUpdated fires on update notification matching regexObj',
        () async {
      final c = buildCollection<String>();
      final received = <CEvent>[];
      final sub = c.events.listen(received.add);

      await c.handleNotification(
        objNotif(
          key: 'id9.$namespace$selfAtSignStr',
          from: selfAtSignStr,
          to: selfAtSignStr,
          operation: 'update',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single, isA<CItemUpdated>());
      expect((received.single as CItemUpdated).id, 'id9');
      expect(received.single.owner, selfAtSign);
      await sub.cancel();
    });

    test('CItemDeleted fires on delete notification', () async {
      final c = buildCollection<String>();
      final received = <CEvent>[];
      final sub = c.events.listen(received.add);

      await c.handleNotification(
        objNotif(
          key: 'id9.$namespace$selfAtSignStr',
          from: bobStr,
          to: selfAtSignStr,
          operation: 'delete',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received.single, isA<CItemDeleted>());
      expect(received.single.owner, bob);
      await sub.cancel();
    });

    test('CReadReceipt fires on read-receipt notification', () async {
      // Set up markRead path — receipt handler calls get() then put(); stub
      // them to return a minimal CItem round-trip.
      final selfKey = AtKey.fromString('id9.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'v'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);

      final c = buildCollection<String>();
      final received = <CEvent>[];
      final sub = c.events.listen(received.add);

      // Read-receipt key form: @to:<rrId>.__rr.<objId>.<ns>@from
      final readAtMicros =
          DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      await c.handleNotification(
        AtNotification(
          'nid-rr',
          '$selfAtSignStr:$readAtMicros.__rr.id9.$namespace$bobStr',
          bobStr,
          selfAtSignStr,
          DateTime.now().millisecondsSinceEpoch,
          'key',
          false,
          operation: 'update',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single, isA<CReadReceipt>());
      final rr = received.single as CReadReceipt;
      expect(rr.id, 'id9');
      expect(rr.from, bob);
      await sub.cancel();
    });

    test('non-matching notification produces no event and does not throw',
        () async {
      final c = buildCollection<String>();
      final received = <CEvent>[];
      final sub = c.events.listen(received.add);

      await c.handleNotification(
        objNotif(
          key: 'some.other.namespace@alice',
          from: selfAtSignStr,
          to: selfAtSignStr,
          operation: 'update',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  group('read receipts', () {
    test('sentReadReceipt returns true for items owned by self (no-op case)',
        () async {
      final c = buildCollection<String>();
      final item = c.create(obj: 'x');
      expect(await c.sentReadReceipt(item), isTrue);
      // No regex scan should have been issued for self-owned items.
      verifyNever(() => atClient.getKeys(regex: any(named: 'regex')));
    });

    test('sentReadReceipt scans for existing receipt on items owned by others',
        () async {
      when(
        () => atClient.getKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <String>[]);
      final c = buildCollection<String>();
      // Fabricate an item whose owner is bob. Can't use c.create because that
      // sets owner=self; instead issue a getItems round-trip like the real
      // flow would.
      final bobKey = AtKey.fromString('idR.$namespace$bobStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [bobKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'v'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final items = await c.getItemsList();
      expect(items, hasLength(1));
      final fromBob = items.single;
      expect(fromBob.owner, bob);

      expect(await c.sentReadReceipt(fromBob), isFalse);
      verify(() => atClient.getKeys(regex: any(named: 'regex'))).called(1);
    });
  });
}
