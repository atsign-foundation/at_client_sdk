// Tests for the [Query<T>] builder API on [AtCollection<T>].
//
// Query is a value-typed, immutable builder layered on top of
// [AtCollection.getItems] for `fetch()` and
// [AtCollection.updates]/[AtCollection.deletes] for `watch()`. These
// tests exercise the builder surface and the two terminal operations
// against a mocked [AtClient], matching the pattern in
// `at_collections_test.dart`.

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class FakeAtKey extends Fake implements AtKey {}

/// Domain object used across the query suite. Three fields chosen so
/// we can exercise filter + sort on different types.
class Task {
  final String title;
  final bool done;
  final DateTime due;

  Task(this.title, {required this.done, required this.due});

  Map<String, dynamic> toJson() => {
        'title': title,
        'done': done,
        'due': due.toUtc().toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        json['title'] as String,
        done: json['done'] as bool,
        due: DateTime.parse(json['due'] as String),
      );

  @override
  String toString() => 'Task($title, done=$done, due=$due)';
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
    AtCollection.registerFactory<Task>(Task.fromJson, typeTag: 'Task');
  });

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;

  const selfAtSignStr = '@alice';
  final selfAtSign = selfAtSignStr.toAtsign();
  const namespace = 'tasks.app_1.my_apps';

  setUp(() {
    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    when(() => atClient.atSign).thenReturn(selfAtSign);
  });

  tearDown(() async {
    await notifStream.close();
  });

  AtCollection<Task> buildCollection() {
    return AtCollection<Task>.withInjectedNotifications(
      atClient,
      namespace,
      const Duration(days: 7),
      notifications: notifStream.stream,
      fromJson: Task.fromJson,
      typeTag: 'Task',
    );
  }

  /// Seeds the mock [AtClient] so `getAtKeys`/`get` return [tasks] as
  /// self-owned items keyed `<id>.<namespace>@<self>`.
  void seed(Map<String, Task> tasks) {
    final keys = tasks.keys
        .map((id) => AtKey.fromString('$id.$namespace$selfAtSignStr'))
        .toList();
    when(
      () => atClient.getAtKeys(regex: any(named: 'regex')),
    ).thenAnswer((_) async => keys);
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final k = inv.positionalArguments.first as AtKey;
      final id = k.key.split('.').first;
      final task = tasks[id]!;
      final v = AtValue();
      v.value = jsonEncode({
        'type': 'Task',
        'obj': task.toJson(),
      });
      v.metadata = Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().add(const Duration(days: 7));
      return v;
    });
  }

  // Nominal due-dates — ordered earliest to latest so sort expectations
  // read naturally below.
  final d1 = DateTime.utc(2026, 04, 01);
  final d2 = DateTime.utc(2026, 04, 15);
  final d3 = DateTime.utc(2026, 05, 01);
  final d4 = DateTime.utc(2026, 05, 20);

  // ---------------------------------------------------------------------------
  group('query() — pass-through', () {
    test('with no modifiers, fetch() equals getItems()', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d2),
        'b': Task('bravo', done: true, due: d1),
      });
      final viaQuery = await c.query().fetch();
      final viaGetItems = await c.getItems();
      expect(viaQuery.map((i) => i.id).toSet(),
          viaGetItems.map((i) => i.id).toSet());
    });
  });

  // ---------------------------------------------------------------------------
  group('where()', () {
    test('single predicate filters', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final open = await c.query().where((t) => !t.obj.done).fetch();
      expect(open.map((i) => i.obj.title).toSet(), {'alpha', 'charlie'});
    });

    test('multiple where() calls AND together', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final overdueOpen = await c
          .query()
          .where((t) => !t.obj.done)
          .where((t) => t.obj.due.isBefore(d2))
          .fetch();
      expect(overdueOpen, hasLength(1));
      expect(overdueOpen.single.obj.title, 'alpha');
    });

    test('where() with no matches returns empty list', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: true, due: d1)});
      final none = await c.query().where((t) => !t.obj.done).fetch();
      expect(none, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('orderBy()', () {
    test('sorts ascending by default on a DateTime key', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
      });
      final sorted = await c.query().orderBy((t) => t.obj.due).fetch();
      expect(sorted.map((i) => i.obj.title), ['bravo', 'charlie', 'alpha']);
    });

    test('descending: true reverses order', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
      });
      final sorted =
          await c.query().orderBy((t) => t.obj.due, descending: true).fetch();
      expect(sorted.map((i) => i.obj.title), ['alpha', 'charlie', 'bravo']);
    });

    test('sort key can be a String', () async {
      final c = buildCollection();
      seed({
        'a': Task('charlie', done: false, due: d1),
        'b': Task('alpha', done: false, due: d1),
        'c': Task('bravo', done: false, due: d1),
      });
      final sorted = await c.query().orderBy((t) => t.obj.title).fetch();
      expect(sorted.map((i) => i.obj.title), ['alpha', 'bravo', 'charlie']);
    });

    test('last orderBy() replaces earlier ones', () async {
      final c = buildCollection();
      seed({
        'a': Task('charlie', done: false, due: d3),
        'b': Task('alpha', done: false, due: d1),
        'c': Task('bravo', done: false, due: d2),
      });
      final sorted = await c
          .query()
          .orderBy((t) => t.obj.title) // would give alpha/bravo/charlie
          .orderBy(
              (t) => t.obj.due) // wins — bravo (d1)/charlie(d2)/alpha(d3)? no
          .fetch();
      // Orders by due: b(d1), c(d2), a(d3). Titles: alpha(a), bravo(b), charlie(c) → b, c, a.
      expect(sorted.map((i) => i.id), ['b', 'c', 'a']);
    });
  });

  // ---------------------------------------------------------------------------
  group('limit() / skip()', () {
    test('limit() truncates after sort', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
        'd': Task('delta', done: false, due: d4),
      });
      final top2 = await c.query().orderBy((t) => t.obj.due).limit(2).fetch();
      expect(top2.map((i) => i.id), ['b', 'c']);
    });

    test('skip() advances past the first n items', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
        'd': Task('delta', done: false, due: d4),
      });
      final afterFirst =
          await c.query().orderBy((t) => t.obj.due).skip(2).fetch();
      expect(afterFirst.map((i) => i.id), ['a', 'd']);
    });

    test('skip() + limit() paginate', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
        'd': Task('delta', done: false, due: d4),
      });
      final page2 =
          await c.query().orderBy((t) => t.obj.due).skip(2).limit(1).fetch();
      expect(page2.map((i) => i.id), ['a']);
    });

    test('limit(0) returns empty', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final none = await c.query().limit(0).fetch();
      expect(none, isEmpty);
    });

    test('limit() rejects negative values', () {
      final c = buildCollection();
      expect(() => c.query().limit(-1), throwsArgumentError);
    });

    test('skip() rejects negative values', () {
      final c = buildCollection();
      expect(() => c.query().skip(-1), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  group('immutability', () {
    test('chained modifiers do not mutate the base query', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final base = c.query();
      final open = base.where((t) => !t.obj.done);
      final done = base.where((t) => t.obj.done);

      expect((await open.fetch()).map((i) => i.id).toSet(), {'a', 'c'});
      expect((await done.fetch()).map((i) => i.id).toSet(), {'b'});
      // Base is still unfiltered — confirming the two branches are
      // independent from each other and from the base.
      expect((await base.fetch()).map((i) => i.id).toSet(), {'a', 'b', 'c'});
    });
  });

  // ---------------------------------------------------------------------------
  group('watch()', () {
    AtNotification objNotif({
      required String key,
      required String from,
      required String to,
      required String operation,
    }) {
      return AtNotification(
        'nid',
        key,
        from,
        to,
        DateTime.now().millisecondsSinceEpoch,
        'key',
        false,
        operation: operation,
      );
    }

    test('emits an initial snapshot on first listen', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
      });
      final q = c.query().where((t) => !t.obj.done);
      final snapshots = <List<CItem<Task>>>[];
      final sub = q.watch().listen(snapshots.add);
      // Let the onListen / fetch complete.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots, hasLength(1));
      expect(snapshots.single.single.id, 'a');
      await sub.cancel();
    });

    test('re-emits on a CItemUpdated notification', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final q = c.query();
      final snapshots = <List<CItem<Task>>>[];
      final sub = q.watch().listen(snapshots.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots, hasLength(1));

      notifStream.add(objNotif(
        key: 'a.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.length, greaterThanOrEqualTo(2));
      await sub.cancel();
    });

    test('re-emits on a CItemDeleted notification', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final q = c.query();
      final snapshots = <List<CItem<Task>>>[];
      final sub = q.watch().listen(snapshots.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots, hasLength(1));

      notifStream.add(objNotif(
        key: 'a.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'delete',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.length, greaterThanOrEqualTo(2));
      await sub.cancel();
    });

    test('cancel stops further emissions', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final q = c.query();
      final snapshots = <List<CItem<Task>>>[];
      final sub = q.watch().listen(snapshots.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final countAfterInitial = snapshots.length;

      await sub.cancel();

      notifStream.add(objNotif(
        key: 'a.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.length, countAfterInitial);
    });
  });

  // ---------------------------------------------------------------------------
  group('composition', () {
    test('where → orderBy → skip → limit applies in the documented order',
        () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: true, due: d1),
        'c': Task('charlie', done: false, due: d2),
        'd': Task('delta', done: false, due: d4),
        'e': Task('echo', done: false, due: d1),
      });
      // Filter out done=true (loses 'b'), order by due asc ('e' d1,
      // 'c' d2, 'a' d3, 'd' d4), skip 1 ('c' first), limit 2.
      final page = await c
          .query()
          .where((t) => !t.obj.done)
          .orderBy((t) => t.obj.due)
          .skip(1)
          .limit(2)
          .fetch();
      expect(page.map((i) => i.id), ['c', 'a']);
    });
  });

  // ---------------------------------------------------------------------------
  group('count()', () {
    test('returns length of the fully-applied result', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final n = await c.query().where((t) => !t.obj.done).count();
      expect(n, 2);
    });

    test('respects limit', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final n = await c.query().limit(2).count();
      expect(n, 2);
    });
  });

  // ---------------------------------------------------------------------------
  group('any()', () {
    test('true when at least one item passes predicates', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: true, due: d1),
        'b': Task('bravo', done: false, due: d2),
      });
      expect(await c.query().where((t) => !t.obj.done).any(), isTrue);
    });

    test('false when nothing matches', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: true, due: d1)});
      expect(await c.query().where((t) => !t.obj.done).any(), isFalse);
    });

    test('inline predicate ANDs with where clauses', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d3),
      });
      final anyOverdue = await c
          .query()
          .where((t) => !t.obj.done)
          .any((t) => t.obj.due.isBefore(d2));
      expect(anyOverdue, isTrue);
    });

    test('false on an empty collection', () async {
      final c = buildCollection();
      seed(<String, Task>{});
      expect(await c.query().any(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('first() / firstOrNull()', () {
    test('firstOrNull returns null when nothing matches', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: true, due: d1)});
      final r = await c.query().where((t) => !t.obj.done).firstOrNull();
      expect(r, isNull);
    });

    test('first() throws StateError when nothing matches', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: true, due: d1)});
      expect(
        () => c.query().where((t) => !t.obj.done).first(),
        throwsStateError,
      );
    });

    test('firstOrNull with orderBy returns the sort-minimum', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
      });
      final r = await c.query().orderBy((t) => t.obj.due).firstOrNull();
      expect(r?.id, 'b');
    });

    test('firstOrNull without orderBy returns an arbitrary matching item',
        () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d2),
      });
      final r = await c.query().where((t) => !t.obj.done).firstOrNull();
      expect(r, isNotNull);
      expect({'a', 'b'}, contains(r!.id));
    });

    test('firstOrNull respects skip when orderBy is set', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
      });
      final r = await c.query().orderBy((t) => t.obj.due).skip(1).firstOrNull();
      // Order: b (d1), c (d2), a (d3). Skip 1 → c is first.
      expect(r?.id, 'c');
    });

    test('limit(0) forces firstOrNull to return null', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final r = await c.query().limit(0).firstOrNull();
      expect(r, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('readReceiptsFor / CItem.receipts', () {
    test('readReceiptsFor returns a query-able AtCollection', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final items = await c.query().fetch();
      final item = items.single;
      final receipts = c.readReceiptsFor(item);
      // It's a proper AtCollection — we can build a Query from it.
      final q = receipts.query();
      expect(q, isNotNull);
      // Sub-collection's namespace is the `__rr` form scoped to the
      // parent item id + owner.
      expect(
          receipts.namespace, contains(AtCollection.readReceiptNamespacePart));
      expect(receipts.namespace, contains(item.id));
    });

    test('CItem.receipts delegates to AtCollection.readReceiptsFor', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final item = (await c.query().fetch()).single;
      expect(identical(item.receipts, c.readReceiptsFor(item)), isTrue);
    });

    test('memoised per (owner, id) across calls', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final item = (await c.query().fetch()).single;
      final a = c.readReceiptsFor(item);
      final b = c.readReceiptsFor(item);
      expect(identical(a, b), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('groupBy()', () {
    test('buckets items by the key function', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final byDone = await c.query().groupBy<bool>((t) => t.obj.done);
      expect(byDone[false]!.map((i) => i.id).toSet(), {'a', 'c'});
      expect(byDone[true]!.map((i) => i.id).toSet(), {'b'});
    });

    test('respects the full spec before grouping', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
        'd': Task('delta', done: false, due: d4),
      });
      final byDone = await c
          .query()
          .where((t) => !t.obj.done) // filters out b
          .orderBy((t) => t.obj.due) // a(d1), c(d3), d(d4)
          .limit(2) // a, c
          .groupBy<bool>((t) => t.obj.done);
      expect(byDone.keys, [false]);
      expect(byDone[false]!.map((i) => i.id), ['a', 'c']);
    });

    test('preserves fetch order within each bucket', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d3),
        'c': Task('charlie', done: true, due: d2),
      });
      final byDone = await c
          .query()
          .orderBy((t) => t.obj.due)
          .groupBy<bool>((t) => t.obj.done);
      // Order across fetch: a (d1, !done), c (d2, done), b (d3, !done).
      expect(byDone[false]!.map((i) => i.id), ['a', 'b']);
      expect(byDone[true]!.map((i) => i.id), ['c']);
    });
  });
}
