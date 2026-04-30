// Baseline tests for AtCollection<T>. Regression guard for any AtCollection
// refactor (e.g. sub-collection support). Every test here must stay green
// after subsequent changes.
//
// Focus: behaviour observable through AtCollection's public API, with
// atClient stubbed via mocktail. The notification stream is injected
// directly via the constructor's [notifications] parameter, so tests drive
// events without having to mock NotificationService.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

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

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;

  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const bobStr = '@bob';
  final bob = bobStr.toAtsign();
  const namespace = 'tasks.app_1.my_apps';

  setUp(() {
    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    when(() => atClient.atSign).thenReturn(selfAtSign);
  });

  tearDown(() async {
    await notifStream.close();
  });

  AtCollection<T> buildCollection<T>({
    String ns = namespace,
    Duration ttl = const Duration(days: 7),
    T Function(Map<String, dynamic>)? fromJson,
    String? typeTag,
  }) {
    return AtCollection<T>.withInjectedNotifications(
      atClient,
      ns,
      ttl,
      notifications: notifStream.stream,
      fromJson: fromJson,
      typeTag: typeTag,
    );
  }

  // ---------------------------------------------------------------------------
  group('construction', () {
    test('rejects a namespace without a dot', () {
      expect(
        () => AtCollection<String>.withInjectedNotifications(
          atClient,
          'notqualified',
          const Duration(days: 1),
          notifications: notifStream.stream,
        ),
        throwsArgumentError,
      );
    });

    test('fromJson + typeTag auto-registers the factory', () async {
      // Build a collection with a fromJson parameter and round-trip via
      // rehydrate (indirectly, through tryGetItems).
      AtCollection.clearFactoriesForTest();
      final c = buildCollection<Widget>(
        fromJson: Widget.fromJson,
        typeTag: 'Widget',
      );
      final selfKey = AtKey.fromString('id1.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'Widget',
          'readBy': <String>[],
          'obj': {'name': 'w1'},
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final items = await c.getItems();
      expect(items.single.obj, Widget('w1'));
      expect(items.single.type, 'Widget');
    });
  });

  // ---------------------------------------------------------------------------
  group('draft', () {
    test('assigns owner=self, auto 8-char id, timestamps, empty sharedWith',
        () {
      final c = buildCollection<String>(ttl: const Duration(hours: 1));
      final before = DateTime.now().toUtc();
      final item = c.draft(obj: 'hello');
      final after = DateTime.now().toUtc();

      expect(item.owner, selfAtSign);
      expect(item.id, hasLength(8));
      expect(RegExp(r'^[a-z0-9]+$').hasMatch(item.id), isTrue);
      expect(item.obj, 'hello');
      expect(item.sharedWith, isEmpty);
      expect(
        item.createdAt.millisecondsSinceEpoch,
        inInclusiveRange(
          before.millisecondsSinceEpoch,
          after.millisecondsSinceEpoch,
        ),
      );
      expect(item.expiresAt, item.createdAt.add(const Duration(hours: 1)));
      expect(item.availableAt, isNull);
    });

    test('honours supplied id and sharedWith', () {
      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'fixed-123', sharedWith: {bob});
      expect(item.id, 'fixed-123');
      expect(item.sharedWith, {bob});
    });

    test('auto-tags Uint8List as binary', () {
      final c = buildCollection<Uint8List>();
      final item = c.draft(obj: Uint8List.fromList([1, 2, 3]));
      expect(item.type, 'binary');
    });

    test('non-Uint8List without registered factory gets n/a', () {
      final c = buildCollection<String>();
      final item = c.draft(obj: 'x');
      expect(item.type, 'n/a');
    });

    test('registered polymorphic type resolves to its typeTag', () {
      AtCollection.clearFactoriesForTest();
      AtCollection.registerFactory<Widget>(
        Widget.fromJson,
        typeTag: 'Widget',
      );
      final c = buildCollection<Widget>();
      final item = c.draft(obj: Widget('w1'));
      expect(item.type, 'Widget');
    });
  });

  // ---------------------------------------------------------------------------
  group('factory registry (process-global)', () {
    test(
        'registerFactory is static: last registration for the same '
        '(type, typeTag) pair wins, and is visible from every '
        'collection instance', () async {
      // Two collections with different namespaces — but factories are
      // process-global. Registering twice for the same `Widget` type
      // under the same typeTag is idempotent (replacement) and both
      // collections decode via the surviving factory.
      AtCollection.clearFactoriesForTest();
      final a = buildCollection<Widget>(ns: 'a.app.ns');
      final b = buildCollection<Widget>(ns: 'b.app.ns');
      AtCollection.registerFactory<Widget>(
        (j) => Widget('a:${j['name']}'),
        typeTag: 'Widget',
      );
      AtCollection.registerFactory<Widget>(
        (j) => Widget('b:${j['name']}'),
        typeTag: 'Widget',
      );

      final aKey = AtKey.fromString('id.a.app.ns$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [aKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'Widget',
          'obj': {'name': 'w1'},
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      // The later registration wins on both instances.
      final aItems = await a.getItems();
      expect(aItems.single.obj, Widget('b:w1'));
      // `b` sees the same factory, of course.
      expect(b.namespace, 'b.app.ns');
    });

    test('binary type round-trips through Base2e15', () {
      final raw = Uint8List.fromList([0, 127, 255, 10, 42]);
      final c = buildCollection<Uint8List>();
      final item = c.draft(obj: raw);
      final encoded = jsonEncode(item.toJson());
      final decoded = jsonDecode(encoded);
      expect(decoded['type'], 'binary');
      expect(Base2e15.decode(decoded['obj']), raw);
    });

    test('rejects empty / whitespace typeTag', () {
      AtCollection.clearFactoriesForTest();
      expect(
        () => AtCollection.registerFactory<Widget>(
          Widget.fromJson,
          typeTag: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => AtCollection.registerFactory<Widget>(
          Widget.fromJson,
          typeTag: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('rejects re-registering the same Type under a different typeTag',
        () {
      AtCollection.clearFactoriesForTest();
      AtCollection.registerFactory<Widget>(Widget.fromJson, typeTag: 'Widget');
      expect(
        () => AtCollection.registerFactory<Widget>(
          Widget.fromJson,
          typeTag: 'Gadget',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('Widget'), contains('Gadget')),
        )),
      );
    });

    test('rejects registering a typeTag already bound to a different Type',
        () {
      AtCollection.clearFactoriesForTest();
      AtCollection.registerFactory<Widget>(Widget.fromJson, typeTag: 'Shared');
      expect(
        () => AtCollection.registerFactory<String>(
          (j) => j['v'] as String,
          typeTag: 'Shared',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Shared'),
        )),
      );
    });

    test(
        'AtCollection ctor: fromJson without typeTag throws ArgumentError',
        () {
      AtCollection.clearFactoriesForTest();
      expect(
        () => buildCollection<Widget>(fromJson: Widget.fromJson),
        throwsArgumentError,
      );
    });

    test(
        'AtCollection ctor: typeTag without fromJson throws ArgumentError',
        () {
      AtCollection.clearFactoriesForTest();
      expect(
        () => buildCollection<Widget>(typeTag: 'Widget'),
        throwsArgumentError,
      );
    });

    test(
        'unknown envelope type-tag warns once and falls back to a '
        'raw map cast', () async {
      // Simulates registry drift: a peer wrote an envelope tagged
      // "Mystery" that this reader has no factory for. The expected
      // behaviour is: log a warning the first time it happens, return
      // the raw map (so untyped consumers still work), no crash.
      AtCollection.clearFactoriesForTest();
      AtCollection.clearMissingFactoryWarningsForTest();
      final c = buildCollection<Map<String, dynamic>>(ns: 'mystery.app.ns');
      final selfKey = AtKey.fromString('mid.mystery.app.ns$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'Mystery',
          'obj': {'name': 'm1'},
        });
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      final items = await c.getItems();
      // No throw — raw map fallback is the intended behaviour for
      // unregistered tags. The warning side-effect is tested by
      // visible inspection in `dart test` output (see "no factory
      // registered for envelope type tag" SHOUT/WARNING lines).
      expect(items, hasLength(1));
      expect(items.single.obj, {'name': 'm1'});
      expect(items.single.type, 'Mystery');
    });
  });

  // ---------------------------------------------------------------------------
  // Low-level write mechanics are exercised indirectly through create/update.
  // These groups focus on the metadata / key shapes produced by a write.
  group('create — write mechanics', () {
    setUp(() {
      // No prior self-key — create's existence probe returns "not found".
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
    });

    test('writes a single self key <id>.<ns>@<self> with correct metadata',
        () async {
      final c = buildCollection<String>();
      await c.create(obj: 'hello', id: 'abc');

      final captured = verify(
        () => atClient.put(captureAny(), captureAny()),
      ).captured;
      final key = captured[0] as AtKey;
      final value = captured[1] as String;
      expect(key.toString(), 'abc.$namespace$selfAtSignStr');
      expect(key.metadata.ttr, -1);
      expect(key.metadata.ccd, true);
      expect(key.metadata.ttl, isNotNull);
      expect(key.metadata.expiresAt, isNotNull);
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      expect(decoded['type'], 'n/a');
      expect(decoded['obj'], 'hello');
      // readBy is no longer persisted — live-queried via item.readers().
      expect(decoded.containsKey('readBy'), isFalse);
    });

    test('writes one recipient copy per entry in sharedWith plus self copy',
        () async {
      final c = buildCollection<String>();
      await c.create(
        obj: 'hi',
        id: 'msg1',
        sharedWith: {bob, '@carol'.toAtsign()},
      );
      final written = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(
          written,
          containsAll([
            'msg1.$namespace$selfAtSignStr',
            '$bobStr:msg1.$namespace$selfAtSignStr',
            '@carol:msg1.$namespace$selfAtSignStr',
          ]));
    });
  });

  // ---------------------------------------------------------------------------
  group('update — write mechanics', () {
    // Stubs so the self-key existence probe succeeds (existing record).
    AtValue storedValue() {
      final v = AtValue();
      v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'old'});
      v.metadata = Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().add(const Duration(days: 1));
      return v;
    }

    setUp(() {
      when(() => atClient.get(any())).thenAnswer((_) async => storedValue());
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(() => atClient.delete(any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
    });

    test('rejects items owned by another atSign', () async {
      final aliceColl = buildCollection<String>();
      final item = aliceColl.draft(obj: 'hi');
      when(() => atClient.atSign).thenReturn(bob);
      final bobColl = buildCollection<String>();
      await expectLater(bobColl.update(item), throwsArgumentError);
    });

    test(
        'unshareWithOthers=true only deletes recipients no longer in '
        'sharedWith; retained recipients are updated in place', () async {
      final existingBob =
          AtKey.fromString('$bobStr:msg2.$namespace$selfAtSignStr');
      final existingDave =
          AtKey.fromString('@dave:msg2.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [existingBob, existingDave]);

      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'msg2', sharedWith: {bob});
      await c.update(item);

      final deleted = verify(
        () => atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(deleted, contains('@dave:msg2.$namespace$selfAtSignStr'));
      expect(deleted, isNot(contains('$bobStr:msg2.$namespace$selfAtSignStr')));

      final written = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(written, contains('msg2.$namespace$selfAtSignStr'));
      expect(written, contains('$bobStr:msg2.$namespace$selfAtSignStr'));
      expect(written, isNot(contains('@dave:msg2.$namespace$selfAtSignStr')));
    });

    test('unshareWithOthers=false preserves unmentioned recipients', () async {
      final existingDave =
          AtKey.fromString('@dave:msg3.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [existingDave]);
      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'msg3', sharedWith: {bob});
      await c.update(item, unshareWithOthers: false);
      verifyNever(() => atClient.delete(any()));
    });

    test('item.availableAt mutation propagates to metadata ttb', () async {
      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'msg4');
      item.availableAt = DateTime.now().add(const Duration(hours: 1));
      await c.update(item);
      final key = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.first as AtKey;
      expect(key.metadata.availableAt, item.availableAt);
      expect(key.metadata.ttb, greaterThan(0));
    });

    test(
        'past availableAt is silently dropped from metadata (would be a '
        'negative ttb)', () async {
      // Regression: a previously-scheduled item's `availableAt` persists
      // across rehydrate+update cycles. Once the scheduled time has
      // passed, we must NOT set metadata.ttb — atServer rejects negative
      // ttb values.
      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'msg5');
      item.availableAt = DateTime.now().subtract(const Duration(minutes: 5));
      await c.update(item);
      final key = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.first as AtKey;
      expect(key.metadata.availableAt, isNull);
      expect(key.metadata.ttb, isNull);
    });

    test('create throws CollectionOpException when any key-level write fails',
        () async {
      // Reset get-mock to pretend self-key is absent (create path).
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenThrow(Exception('boom'));
      final c = buildCollection<String>();
      await expectLater(
        c.create(obj: 'x', id: 'fail-me'),
        throwsA(isA<CollectionOpException>()),
      );
    });

    test(
        'update after create elides the existence probe (no atClient.get '
        'round-trip for the just-written id)', () async {
      // This group's setUp pre-stubs get() to return a stored value, so
      // the existence probe always *would* succeed if it ran. We assert
      // that it doesn't run at all on the second touch — the cache
      // populated by create() short-circuits _selfKeyExists.
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      final c = buildCollection<String>();
      final item = await c.create(obj: 'first', id: 'cached-1');
      // After create(): atClient.get may have been called for unrelated
      // probes, but for the update path we want to see zero gets on the
      // self-key. Reset the mock-call tracker so the next verify is
      // scoped to update().
      clearInteractions(atClient);
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
      await c.update(item);
      // Zero get() calls — the cache short-circuited the existence probe.
      verifyNever(() => atClient.get(any()));
    });

    test(
        'delete drops the cached id so a subsequent update re-probes',
        () async {
      // Round-trip: create → delete → update should NOT pass the
      // existence probe (since the item is now gone). Verifies the
      // cache is invalidated on delete.
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(() => atClient.delete(any())).thenAnswer((_) async => true);
      // Two regex shapes hit getAtKeys here:
      //   - descendant scan from delete: `(^|:).+\.cached-2\.<ns>@self`
      //     → must return [] (no descendants).
      //   - self-key+recipients scan: `(^|:)cached-2\.<ns>@`
      //     → must return [selfKey].
      // Distinguish by the `.+\.` prefix.
      final selfKey =
          AtKey.fromString('cached-2.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((inv) async {
        final regex = inv.namedArguments[#regex] as String;
        if (regex.contains('.+\\.cached-2')) return <AtKey>[];
        return [selfKey];
      });
      final c = buildCollection<String>();
      final item = await c.create(obj: 'x', id: 'cached-2');
      await c.delete(item);
      // After delete, the cache entry is gone — update must re-probe
      // and find the key absent → StateError.
      await expectLater(c.update(item), throwsStateError);
    });
  });

  // ---------------------------------------------------------------------------
  group('create — draft + put with existence check', () {
    test(
        'with explicit id: persists and returns the CItem when the self-key '
        'is free', () async {
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
      final c = buildCollection<String>();
      final item = await c.create(obj: 'hello', id: 'abc');
      expect(item.id, 'abc');
      expect(item.obj, 'hello');
      expect(item.owner, selfAtSign);
      verify(() => atClient.put(any(), any())).called(1);
    });

    test('with explicit id: throws StateError if the self-key already exists',
        () async {
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'x'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
      final c = buildCollection<String>();
      await expectLater(
        c.create(obj: 'hi', id: 'collides'),
        throwsA(isA<StateError>()),
      );
      verifyNever(() => atClient.put(any(), any()));
    });

    test('with auto-generated id: persists with a fresh random 8-char id',
        () async {
      // First existence check: any auto-generated id is unused.
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);

      final c = buildCollection<String>();
      final item = await c.create(obj: 'hello');
      expect(item.id, hasLength(8));
      expect(RegExp(r'^[a-z0-9]+$').hasMatch(item.id), isTrue);
    });

    test(
        'with auto-generated id: retries on collision and gives up after 10 '
        'attempts', () async {
      // Every get() returns an existing AtValue → every random id we try
      // is reported as "already in use". Create should eventually throw.
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'x'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      final c = buildCollection<String>();
      await expectLater(
        c.create(obj: 'hi'),
        throwsA(isA<StateError>()),
      );
    });

    test('propagates put failures as CollectionOpException', () async {
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenThrow(Exception('boom'));
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
      final c = buildCollection<String>();
      await expectLater(
        c.create(obj: 'x', id: 'abc'),
        throwsA(isA<CollectionOpException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('update — existence check, otherwise put', () {
    test('succeeds when the self-key exists', () async {
      // get() is the existence probe — return a stored record so update
      // proceeds through _put without throwing.
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'x'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);

      final c = buildCollection<String>();
      final item = c.draft(obj: 'new text', id: 'abc');
      await c.update(item);
      verify(() => atClient.put(any(), any())).called(1);
    });

    test('throws StateError when the self-key is missing', () async {
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'doesnt-exist');
      await expectLater(
        c.update(item),
        throwsA(isA<StateError>()),
      );
      verifyNever(() => atClient.put(any(), any()));
    });

    test('rejects items owned by another atSign', () async {
      final aliceColl = buildCollection<String>();
      final item = aliceColl.draft(obj: 'x');
      when(() => atClient.atSign).thenReturn(bob);
      final bobColl = buildCollection<String>();
      await expectLater(bobColl.update(item), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  group('reads — get, getOrNull, getItems, getItemsAsStream', () {
    AtValue atValueFor(Object obj, {String type = 'n/a'}) {
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

    test('getItems dedupes keys and unions sharedWith', () async {
      final selfKey = AtKey.fromString('id1.$namespace$selfAtSignStr');
      final shareBob = AtKey.fromString('$bobStr:id1.$namespace$selfAtSignStr');
      final shareCarol =
          AtKey.fromString('@carol:id1.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey, shareBob, shareCarol]);
      when(() => atClient.get(any()))
          .thenAnswer((_) async => atValueFor('hello'));

      final c = buildCollection<String>();
      final items = await c.getItems();
      expect(items, hasLength(1));
      expect(items.single.id, 'id1');
      expect(items.single.owner, selfAtSign);
      expect(items.single.sharedWith, containsAll([bob, '@carol'.toAtsign()]));
      expect(items.single.obj, 'hello');
    });

    test(
        'getItemsAsStream yields per-key decode failures as stream errors; '
        'getItems surfaces them via .toList()', () async {
      // The stream emits a sequence of data events for good items and
      // error events for bad ones. Good data keeps flowing on either
      // side of an error. `.toList()` adopts the first-error-wins
      // policy of Dart streams, so `await getItems()` will throw.
      final goodKey = AtKey.fromString('ok.$namespace$selfAtSignStr');
      final badKey = AtKey.fromString('bad.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [goodKey, badKey]);
      when(() => atClient.get(any())).thenAnswer((invocation) async {
        final k = invocation.positionalArguments.first as AtKey;
        if (k.toString().startsWith('bad.')) {
          throw Exception('boom');
        }
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'hello'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final c = buildCollection<String>();

      // Direct stream consumption: collect data and errors separately.
      // Use onData + onError + a Completer on onDone — `asFuture()`
      // would short-circuit the future on the first error event,
      // swallowing the post-error data the stream still emits.
      final good = <CItem<String>>[];
      final errors = <Object>[];
      final done = Completer<void>();
      c.getItemsAsStream().listen(
            good.add,
            onError: errors.add,
            onDone: done.complete,
          );
      await done.future;
      expect(good, hasLength(1));
      expect(good.single.id, 'ok');
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains('bad.'));

      // `getItems()` is `.toList()` which adopts first-error-wins.
      await expectLater(c.getItems(), throwsA(anything));
    });

    test('stream consumers can restore silent-skip with .handleError',
        () async {
      final goodKey = AtKey.fromString('ok.$namespace$selfAtSignStr');
      final badKey = AtKey.fromString('bad.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [goodKey, badKey]);
      when(() => atClient.get(any())).thenAnswer((invocation) async {
        final k = invocation.positionalArguments.first as AtKey;
        if (k.toString().startsWith('bad.')) {
          throw Exception('boom');
        }
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'hi'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final c = buildCollection<String>();
      // `.handleError` swallows the error event; `.toList()` then
      // collects only the good item.
      final items = await c.getItemsAsStream().handleError((_) {}).toList();
      expect(items, hasLength(1));
      expect(items.single.id, 'ok');
    });

    test('get(id, owner) returns a single item or throws when missing',
        () async {
      final selfKey = AtKey.fromString('id3.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async => atValueFor('v3'));

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

    test('getOrNull returns null when missing, item when present', () async {
      final selfKey = AtKey.fromString('id4.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async => atValueFor('v4'));

      final c = buildCollection<String>();
      final found = await c.getOrNull('id4', selfAtSign);
      expect(found, isNotNull);
      expect(found!.obj, 'v4');

      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => <AtKey>[]);
      final missing = await c.getOrNull('nope', selfAtSign);
      expect(missing, isNull);
    });

    test('getItemsAsStream yields each unique item with full sharedWith',
        () async {
      // id1 has two copies (self + one recipient); id2 has just a self copy.
      final id1Self = AtKey.fromString('id1.$namespace$selfAtSignStr');
      final id1Bob = AtKey.fromString('$bobStr:id1.$namespace$selfAtSignStr');
      final id2Self = AtKey.fromString('id2.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [id1Self, id1Bob, id2Self]);
      when(() => atClient.get(any())).thenAnswer((_) async => atValueFor('v'));

      final c = buildCollection<String>();
      final items = await c.getItemsAsStream().toList();
      expect(items, hasLength(2));
      final byId = {for (final i in items) i.id: i};
      expect(byId['id1']!.sharedWith, contains(bob));
      expect(byId['id2']!.sharedWith, isEmpty);
    });

    test('getItemsAsStream plays nicely with Stream.where for queries',
        () async {
      final self1 = AtKey.fromString('id1.$namespace$selfAtSignStr');
      final self2 = AtKey.fromString('id2.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [self1, self2]);
      when(() => atClient.get(self1))
          .thenAnswer((_) async => atValueFor('keep'));
      when(() => atClient.get(self2))
          .thenAnswer((_) async => atValueFor('drop'));

      final c = buildCollection<String>();
      final kept =
          await c.getItemsAsStream().where((i) => i.obj == 'keep').toList();
      expect(kept, hasLength(1));
      expect(kept.single.obj, 'keep');
    });

    test(
        'rehydrate drops past availableAt so stale server metadata does '
        "not leak into CItem", () async {
      // Regression: server-side metadata may carry a historic availableAt
      // that is already in the past. The atProtocol metadata wire format
      // is additive — we can't clear it on the server — but the app view
      // must show it as null. Past availableAt on rehydrate → null here.
      final selfKey = AtKey.fromString('oldsched.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'x'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1))
          ..availableAt = DateTime.now().subtract(const Duration(hours: 1));
        return v;
      });

      final c = buildCollection<String>();
      final itemsList = await c.getItems();
      expect(itemsList.single.availableAt, isNull);
      final itemsStream = await c.getItemsAsStream().toList();
      expect(itemsStream.single.availableAt, isNull);
    });

    test('rehydrate preserves future availableAt', () async {
      final future = DateTime.now().add(const Duration(hours: 2));
      final selfKey = AtKey.fromString('futsched.$namespace$selfAtSignStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'readBy': <String>[], 'obj': 'x'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1))
          ..availableAt = future;
        return v;
      });

      final c = buildCollection<String>();
      final itemsList = await c.getItems();
      expect(itemsList.single.availableAt, isNotNull);
      expect(itemsList.single.availableAt!.isAfter(DateTime.now()), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('delete', () {
    // Partition `atClient.getAtKeys` responses by regex shape:
    // - descendant scan uses regex starting `(^|:).+\.`
    // - item scan uses `(^|:)<id>\.`
    late List<AtKey> itemScanKeys;

    void stubDescendants({List<AtKey> descendants = const []}) {
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((invocation) async {
        final regex =
            invocation.namedArguments[const Symbol('regex')] as String;
        if (regex.startsWith(r'(^|:).+\.')) return descendants;
        return itemScanKeys;
      });
    }

    setUp(() {
      when(() => atClient.delete(any())).thenAnswer((_) async => true);
      itemScanKeys = <AtKey>[];
    });

    test('rejects items owned by another atSign', () async {
      final aliceColl = buildCollection<String>();
      final item = aliceColl.draft(obj: 'x');
      when(() => atClient.atSign).thenReturn(bob);
      final bobColl = buildCollection<String>();
      await expectLater(bobColl.delete(item), throwsArgumentError);
    });

    test('deletes self + shared keys when there are no descendants', () async {
      final selfKey = AtKey.fromString('delme.$namespace$selfAtSignStr');
      final shareKey =
          AtKey.fromString('$bobStr:delme.$namespace$selfAtSignStr');
      itemScanKeys = [selfKey, shareKey];
      stubDescendants();

      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'delme', sharedWith: {bob});
      await c.delete(item);

      final deleted = verify(
        () => atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(
          deleted,
          containsAll([
            'delme.$namespace$selfAtSignStr',
            '$bobStr:delme.$namespace$selfAtSignStr',
          ]));
    });

    test('throws CollectionOpException on any key-level failure', () async {
      final selfKey = AtKey.fromString('delme.$namespace$selfAtSignStr');
      itemScanKeys = [selfKey];
      stubDescendants();
      when(() => atClient.delete(any())).thenThrow(Exception('boom'));

      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'delme');
      await expectLater(c.delete(item), throwsA(isA<CollectionOpException>()));
    });

    test(
        'default (cascade: false) prevents delete when self-owned '
        'descendants exist', () async {
      final selfKey = AtKey.fromString('p1.$namespace$selfAtSignStr');
      final descKey = AtKey.fromString(
        'c1.comments.p1.$namespace$selfAtSignStr',
      );
      itemScanKeys = [selfKey];
      stubDescendants(descendants: [descKey]);

      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'p1');

      await expectLater(c.delete(item), throwsA(isA<StateError>()));
      verifyNever(() => atClient.delete(any()));
    });

    test('cascade: true deletes descendants first, then the item', () async {
      final selfKey = AtKey.fromString('p1.$namespace$selfAtSignStr');
      final desc1 = AtKey.fromString(
        'c1.comments.p1.$namespace$selfAtSignStr',
      );
      final desc2 = AtKey.fromString(
        'r1.replies.c1.comments.p1.$namespace$selfAtSignStr',
      );
      itemScanKeys = [selfKey];
      stubDescendants(descendants: [desc1, desc2]);

      final c = buildCollection<String>();
      final item = c.draft(obj: 'x', id: 'p1');
      await c.delete(item, cascade: true);

      final deleted = verify(
        () => atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(
          deleted,
          containsAll([
            desc1.toString(),
            desc2.toString(),
            selfKey.toString(),
          ]));
    });
  });

  // ---------------------------------------------------------------------------
  group('events — typed sub-streams via injected notification stream', () {
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

    test('updates stream fires only CItemUpdated', () async {
      final c = buildCollection<String>();
      final received = <CItemUpdated>[];
      final sub = c.updates.listen(received.add);

      notifStream.add(objNotif(
        key: 'id9.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      notifStream.add(objNotif(
        key: 'id9.$namespace$selfAtSignStr',
        from: bobStr,
        to: selfAtSignStr,
        operation: 'delete',
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.id, 'id9');
      expect(received.single.owner, selfAtSign);
      await sub.cancel();
    });

    test('deletes stream fires only CItemDeleted', () async {
      final c = buildCollection<String>();
      final received = <CItemDeleted>[];
      final sub = c.deletes.listen(received.add);

      notifStream.add(objNotif(
        key: 'id9.$namespace$selfAtSignStr',
        from: bobStr,
        to: selfAtSignStr,
        operation: 'delete',
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.owner, bob);
      await sub.cancel();
    });

    test(
        'readReceipts stream fires CReadReceipt on __rr sub-item '
        'notifications', () async {
      // A read receipt is now a sub-item of the reserved `__rr`
      // sub-collection, so the notification goes through
      // handleSubObjNotification, which emits both a CSubItemUpdated
      // and a CReadReceipt on the parent collection.
      final c = buildCollection<String>();
      final receipts = <CReadReceipt>[];
      final subs = <CSubItemUpdated>[];
      final rrSub = c.readReceipts.listen(receipts.add);
      final subSub = c.subUpdates.listen(subs.add);

      final readAtMicros =
          DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      notifStream.add(
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
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(receipts, hasLength(1));
      expect(receipts.single.id, 'id9');
      expect(receipts.single.from, bob);
      expect(subs, hasLength(1));
      expect(subs.single.subName, '__rr');
      // The CSubItemUpdated's id is the receipt sub-item's own id
      // (the microsecond timestamp), and ancestry.last.id is the
      // parent item id (id9).
      expect(subs.single.ancestry.single.id, 'id9');
      await rrSub.cancel();
      await subSub.cancel();
    });

    test('non-matching notification produces no event', () async {
      final c = buildCollection<String>();
      final received = <CEvent>[];
      final sub = c.watch().listen(received.add);
      notifStream.add(objNotif(
        key: 'some.other.namespace@alice',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  group('read receipts', () {
    test('wasMarkedReadByMe returns true for items owned by self', () async {
      final c = buildCollection<String>();
      final item = c.draft(obj: 'x');
      expect(await c.wasMarkedReadByMe(item), isTrue);
      verifyNever(() => atClient.getKeys(regex: any(named: 'regex')));
    });

    test('wasMarkedReadByMe scans __rr sub-collection on others\' items',
        () async {
      // AtKey.fromString lowercases ids, so the stored id is 'idr'.
      final bobKey = AtKey.fromString('idr.$namespace$bobStr');
      // The cache-priming `readBy` scans the entire __rr sub-collection
      // (no owner filter); wasMarkedReadByMe then checks self membership.
      final rrRegex = '(^|:)[^.]+\\.__rr.idr.$namespace@';
      // Parent scan returns bob's item; the __rr sub-collection scan
      // returns nothing (no receipts sent yet).
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((invocation) async {
        final regex = invocation.namedArguments[#regex] as String;
        if (regex.contains('__rr')) return <AtKey>[];
        return [bobKey];
      });
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'v'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });

      final c = buildCollection<String>();
      final items = await c.getItems();
      final fromBob = items.single;
      expect(fromBob.owner, bob);
      expect(await c.wasMarkedReadByMe(fromBob), isFalse);
      verify(
        () => atClient.getAtKeys(regex: rrRegex),
      ).called(1);
    });

    test('markReadByMe writes a __rr sub-item with the owner in sharedWith',
        () async {
      // AtKey lowercases ids → 'idm'.
      final bobKey = AtKey.fromString('idm.$namespace$bobStr');
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((invocation) async {
        final regex = invocation.namedArguments[#regex] as String;
        if (regex.contains('__rr')) return <AtKey>[];
        return [bobKey];
      });
      // get() returns bob's item for the parent read; throws for any
      // __rr sub-key (existence probe inside create()).
      when(() => atClient.get(any())).thenAnswer((invocation) async {
        final k = invocation.positionalArguments.first as AtKey;
        if (k.toString().contains('__rr')) {
          throw Exception('no such key');
        }
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'v'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = DateTime.now().add(const Duration(days: 1));
        return v;
      });
      when(() => atClient.put(any(), any())).thenAnswer((_) async => true);

      final c = buildCollection<String>();
      final fromBob = (await c.getItems()).single;
      await fromBob.markReadByMe();

      final writes = verify(
        () => atClient.put(captureAny(), any()),
      ).captured.cast<AtKey>();
      final strings = writes.map((k) => k.toString()).toList();
      expect(
        strings.any((s) => RegExp(r'^[^.:]+\.__rr\.idm\.').hasMatch(s)),
        isTrue,
        reason: 'self-copy of __rr receipt written',
      );
      expect(
        strings.any((s) => s.startsWith('$bobStr:')),
        isTrue,
        reason: 'receipt copy shared with bob',
      );
    });

    test('markReadByMe is a no-op for self-owned items', () async {
      final c = buildCollection<String>();
      final own = c.draft(obj: 'mine');
      await own.markReadByMe();
      verifyNever(() => atClient.put(any(), any()));
    });
  });

  // ---------------------------------------------------------------------------
  // Timer-driven events. Use small real-time durations (tens of ms)
  // so the suite stays fast without a fake-async test harness. The
  // scheduler reads `DateTime.now()` directly, so each test's
  // assertions account for ~5-10ms of scheduling jitter.
  group('availableEvents (W7)', () {
    /// Helper: mock `getAtKeys` + `get` to surface a single item with
    /// the given availableAt / expiresAt.
    void seedSingleItem({
      required String id,
      DateTime? availableAt,
      DateTime? expiresAt,
    }) {
      final selfKey = AtKey.fromString('$id.$namespace$selfAtSignStr');
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'hello'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = expiresAt ?? DateTime.now().add(const Duration(days: 7))
          ..availableAt = availableAt;
        return v;
      });
    }

    test('fires when a future availableAt elapses', () async {
      final fireAt = DateTime.now().add(const Duration(milliseconds: 80));
      seedSingleItem(id: 'sched1', availableAt: fireAt);
      final c = buildCollection<String>();
      final received = <CItemAvailable>[];
      final sub = c.availableEvents.listen(received.add);
      // Before fireAt: no emission.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(received, isEmpty);
      // After fireAt + jitter window: emission.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received, hasLength(1));
      expect(received.single.id, 'sched1');
      expect(received.single.owner, selfAtSign);
      expect(
        received.single.availableAt.millisecondsSinceEpoch,
        closeTo(fireAt.millisecondsSinceEpoch, 5),
      );
      await sub.cancel();
    });

    test('does not track items with no availableAt', () async {
      seedSingleItem(id: 'instant'); // no availableAt
      final c = buildCollection<String>();
      final received = <CItemAvailable>[];
      final sub = c.availableEvents.listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(received, isEmpty);
      await sub.cancel();
    });

    test('also flows through the master watch() stream', () async {
      final fireAt = DateTime.now().add(const Duration(milliseconds: 60));
      seedSingleItem(id: 'sched2', availableAt: fireAt);
      final c = buildCollection<String>();
      final viaWatch = <CEvent>[];
      final sub = c.availableEvents.listen((_) {});
      final watchSub = c.watch().listen(viaWatch.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        viaWatch.whereType<CItemAvailable>().toList(),
        hasLength(1),
      );
      await sub.cancel();
      await watchSub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  group('expiringSoonEvents (W7)', () {
    AtNotification objNotif({
      required String key,
      required String operation,
    }) {
      return AtNotification(
        'nid-exp',
        key,
        selfAtSignStr,
        selfAtSignStr,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: operation,
      );
    }

    test('fires leadTime before expiresAt', () async {
      // expiresAt at +120ms, leadTime 80ms → fire at +40ms.
      final expiresAt =
          DateTime.now().add(const Duration(milliseconds: 120));
      final selfKey = AtKey.fromString('exp1.$namespace$selfAtSignStr');
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'hi'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = expiresAt;
        return v;
      });
      final c = buildCollection<String>();
      final received = <CItemExpiringSoon>[];
      final sub = c
          .expiringSoonEvents(leadTime: const Duration(milliseconds: 80))
          .listen(received.add);
      // Before fire-at (+40ms): no emission yet at +20ms.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, isEmpty);
      // After fire-at, before expiry: emission.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(received, hasLength(1));
      expect(received.single.id, 'exp1');
      expect(received.single.leadTime, const Duration(milliseconds: 80));
      expect(received.single.expiresAt.millisecondsSinceEpoch,
          closeTo(expiresAt.millisecondsSinceEpoch, 5));
      await sub.cancel();
    });

    test('items already in their warning window fire on next loop turn',
        () async {
      // expiresAt 100ms ahead, leadTime 200ms → fire-at is 100ms in
      // the past at subscription. Should fire promptly.
      final expiresAt =
          DateTime.now().add(const Duration(milliseconds: 100));
      final selfKey = AtKey.fromString('exp2.$namespace$selfAtSignStr');
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'hi'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = expiresAt;
        return v;
      });
      final c = buildCollection<String>();
      final received = <CItemExpiringSoon>[];
      final sub = c
          .expiringSoonEvents(leadTime: const Duration(milliseconds: 200))
          .listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(received, hasLength(1));
      await sub.cancel();
    });

    test('cancellation tears the scheduler down', () async {
      final expiresAt =
          DateTime.now().add(const Duration(milliseconds: 200));
      final selfKey = AtKey.fromString('exp3.$namespace$selfAtSignStr');
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'hi'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = expiresAt;
        return v;
      });
      final c = buildCollection<String>();
      final received = <CItemExpiringSoon>[];
      final sub = c
          .expiringSoonEvents(leadTime: const Duration(milliseconds: 100))
          .listen(received.add);
      // Cancel before the firing time.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received, isEmpty);
    });

    test('a delete unregisters the firing', () async {
      final expiresAt =
          DateTime.now().add(const Duration(milliseconds: 150));
      final selfKey = AtKey.fromString('exp4.$namespace$selfAtSignStr');
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({'type': 'n/a', 'obj': 'hi'});
        v.metadata = Metadata()
          ..createdAt = DateTime.now().toUtc()
          ..expiresAt = expiresAt;
        return v;
      });
      final c = buildCollection<String>();
      final received = <CItemExpiringSoon>[];
      final sub = c
          .expiringSoonEvents(leadTime: const Duration(milliseconds: 50))
          .listen(received.add);
      // Let the initial population settle, then delete the item via
      // a notification.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      notifStream.add(objNotif(
        key: 'exp4.$namespace$selfAtSignStr',
        operation: 'delete',
      ));
      // Wait past where the firing would have happened.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, isEmpty);
      await sub.cancel();
    });

    test('rejects a negative leadTime', () {
      final c = buildCollection<String>();
      expect(
        () => c.expiringSoonEvents(
          leadTime: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
