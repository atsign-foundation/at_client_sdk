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

/// Typed [PathField] accessors for [Task] — used by the wherePath
/// tests to exercise the AST surface.
abstract class $Task {
  static final done = PathField<bool>(
    path: ['obj', 'done'],
    extract: (item) => (item.obj as Task).done,
  );
  static final due = PathField<DateTime>(
    path: ['obj', 'due'],
    extract: (item) => (item.obj as Task).due,
  );
  static final title = PathField<String>(
    path: ['obj', 'title'],
    extract: (item) => (item.obj as Task).title,
  );
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
    return collectionWithInjectedNotifications<Task>(
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
      final viaQuery = await c.query().get();
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
      final open = await c.query().where((t) => !t.obj.done).get();
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
          .get();
      expect(overdueOpen, hasLength(1));
      expect(overdueOpen.single.obj.title, 'alpha');
    });

    test('where() with no matches returns empty list', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: true, due: d1)});
      final none = await c.query().where((t) => !t.obj.done).get();
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
      final sorted = await c.query().orderBy((t) => t.obj.due).get();
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
          await c.query().orderBy((t) => t.obj.due, descending: true).get();
      expect(sorted.map((i) => i.obj.title), ['alpha', 'charlie', 'bravo']);
    });

    test('sort key can be a String', () async {
      final c = buildCollection();
      seed({
        'a': Task('charlie', done: false, due: d1),
        'b': Task('alpha', done: false, due: d1),
        'c': Task('bravo', done: false, due: d1),
      });
      final sorted = await c.query().orderBy((t) => t.obj.title).get();
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
          .get();
      // Orders by due: b(d1), c(d2), a(d3). Titles: alpha(a), bravo(b), charlie(c) → b, c, a.
      expect(sorted.map((i) => i.id), ['b', 'c', 'a']);
    });
  });

  // ---------------------------------------------------------------------------
  group('thenBy()', () {
    test('orderBy + thenBy: tiebreaks within equal primary keys', () async {
      final c = buildCollection();
      // Two tasks share due=d1; thenBy(title) decides their order.
      seed({
        'a': Task('charlie', done: false, due: d1),
        'b': Task('alpha', done: false, due: d1),
        'c': Task('bravo', done: false, due: d2),
      });
      final sorted = await c
          .query()
          .orderBy((t) => t.obj.due)
          .thenBy((t) => t.obj.title)
          .get();
      // d1 group sorted by title (alpha, charlie), then d2 (bravo).
      expect(sorted.map((i) => i.obj.title), ['alpha', 'charlie', 'bravo']);
    });

    test('thenBy honours its own descending flag independently', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
      });
      final sorted = await c
          .query()
          .orderBy((t) => t.obj.due) // primary asc
          .thenBy((t) => t.obj.title, descending: true) // tiebreak desc
          .get();
      // d1 group: bravo before alpha (title desc), then d2 (charlie).
      expect(sorted.map((i) => i.obj.title), ['bravo', 'alpha', 'charlie']);
    });

    test('multiple thenBy calls accumulate in registration order', () async {
      final c = buildCollection();
      // All four share due=d1 and done=false; only difference is title.
      // Use done as the second key (all false → ties), title as the
      // third tiebreaker — verifies a 3-level chain.
      seed({
        'a': Task('charlie', done: false, due: d1),
        'b': Task('alpha', done: false, due: d1),
        'c': Task('bravo', done: false, due: d1),
        'd': Task('delta', done: false, due: d1),
      });
      final sorted = await c
          .query()
          .orderBy((t) => t.obj.due)
          .thenBy((t) => t.obj.done ? 1 : 0)
          .thenBy((t) => t.obj.title)
          .get();
      // Primary tied (all d1), secondary tied (all done=false), tertiary
      // breaks them: alpha, bravo, charlie, delta.
      expect(
        sorted.map((i) => i.obj.title),
        ['alpha', 'bravo', 'charlie', 'delta'],
      );
    });

    test('thenBy without a prior orderBy throws StateError', () {
      final c = buildCollection();
      expect(
        () => c.query().thenBy((t) => t.obj.title),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('orderBy'),
        )),
      );
    });

    test('orderBy after thenBy chain resets to a single key', () async {
      // .orderBy keeps replace semantics: a fresh .orderBy after a chain
      // of .thenBy starts over with just that one key.
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: false, due: d2),
      });
      final sorted = await c
          .query()
          .orderBy((t) => t.obj.title)
          .thenBy((t) => t.obj.due)
          .orderBy((t) => t.obj.due) // resets — only this key remains
          .get();
      expect(sorted.map((i) => i.id), ['b', 'c', 'a']);
    });
  });

  // ---------------------------------------------------------------------------
  group('wherePath() — typed predicate AST', () {
    test('eq filters with the expected semantics', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final open = await c.query().wherePath($Task.done.eq(false)).get();
      expect(open.map((i) => i.obj.title).toSet(), {'alpha', 'charlie'});
    });

    test('lt on a Comparable PathField filters by < value', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final early = await c.query().wherePath($Task.due.lt(d2)).get();
      expect(early.map((i) => i.id), ['a']);
    });

    test('and combinator AND-ses two leaves', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d1),
        'c': Task('charlie', done: false, due: d3),
      });
      final result = await c
          .query()
          .wherePath($Task.done.eq(false).and($Task.due.lt(d2)))
          .get();
      expect(result.map((i) => i.id), ['a']);
    });

    test('or combinator OR-ses two leaves', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final result = await c
          .query()
          .wherePath($Task.title.eq('alpha').or($Task.title.eq('bravo')))
          .get();
      expect(result.map((i) => i.id).toSet(), {'a', 'b'});
    });

    test('not negates the inner predicate', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
      });
      final result = await c.query().wherePath($Task.done.eq(true).not).get();
      expect(result.map((i) => i.id), ['a']);
    });

    test('multiple wherePath calls AND together', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d3),
        'c': Task('charlie', done: true, due: d1),
      });
      final result = await c
          .query()
          .wherePath($Task.done.eq(false))
          .wherePath($Task.due.lt(d2))
          .get();
      expect(result.map((i) => i.id), ['a']);
    });

    test('wherePath composes with closure-based where', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d2),
        'c': Task('charlie', done: false, due: d3),
      });
      final result = await c
          .query()
          .wherePath($Task.done.eq(false))
          .where((t) => t.obj.title.startsWith('b'))
          .get();
      expect(result.map((i) => i.id), ['b']);
    });

    test('Predicate.and flattens nested AND chains', () {
      final p1 = $Task.done.eq(false);
      final p2 = $Task.due.lt(d3);
      final p3 = $Task.title.eq('alpha');
      final composed = p1.and(p2).and(p3);
      expect(composed, isA<AndPredicate>());
      expect((composed as AndPredicate).children, hasLength(3));
    });

    test('Predicate.not collapses double negation', () {
      final p = $Task.done.eq(false);
      expect(p.not.not, same(p));
    });

    test('CmpPredicate exposes its field, op, and value for introspection', () {
      final p = $Task.done.eq(true);
      expect(p, isA<CmpPredicate>());
      final cmp = p as CmpPredicate;
      expect(cmp.op, PredicateOp.eq);
      expect(cmp.value, true);
      expect(cmp.field.path, ['obj', 'done']);
    });

    test(
        'reserved-but-unimplemented PredicateOp values throw UnimplementedError',
        () async {
      // The reserved set is pre-allocated so adding implementations
      // later isn't a breaking enum change. Until those landings,
      // evaluate() on a CmpPredicate built around one must throw a
      // descriptive UnimplementedError so callers find out at use
      // time rather than via silent false-results.
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final items = await c.getItems();
      final item = items.single;
      const reserved = [
        PredicateOp.like,
        PredicateOp.inSet,
        PredicateOp.between,
        PredicateOp.contains,
        PredicateOp.startsWith,
      ];
      for (final op in reserved) {
        final cmp = cmpPredicateForTest($Task.title, op, 'whatever');
        expect(
          () => cmp.evaluate(item),
          throwsA(isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            contains('PredicateOp.${op.name}'),
          )),
        );
      }
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
      final top2 = await c.query().orderBy((t) => t.obj.due).limit(2).get();
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
          await c.query().orderBy((t) => t.obj.due).skip(2).get();
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
          await c.query().orderBy((t) => t.obj.due).skip(2).limit(1).get();
      expect(page2.map((i) => i.id), ['a']);
    });

    test('limit(0) returns empty', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final none = await c.query().limit(0).get();
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

      expect((await open.get()).map((i) => i.id).toSet(), {'a', 'c'});
      expect((await done.get()).map((i) => i.id).toSet(), {'b'});
      // Base is still unfiltered — confirming the two branches are
      // independent from each other and from the base.
      expect((await base.get()).map((i) => i.id).toSet(), {'a', 'b', 'c'});
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

    test(
        'delta path: an update event drives one item fetch, not N '
        '(the whole-collection refetch path is avoided)', () async {
      // The benefit of delta maintenance is O(1) reads per event vs
      // O(N) under the old "full refetch" path. We assert that by
      // seeding 4 items, then triggering a single update event and
      // counting how many atClient.get calls follow — under refetch
      // it would be 4; under delta, exactly 1 (for the affected id).
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d2),
        'c': Task('charlie', done: false, due: d3),
        'd': Task('delta', done: false, due: d4),
      });
      final q = c.query();
      final sub = q.watch().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      clearInteractions(atClient);
      // Re-seed (mocktail's `when` survives clearInteractions for
      // stubs; the call-count tracker is what gets reset).
      seed({
        'a': Task('alpha', done: true, due: d1),
        'b': Task('bravo', done: false, due: d2),
        'c': Task('charlie', done: false, due: d3),
        'd': Task('delta', done: false, due: d4),
      });
      notifStream.add(objNotif(
        key: 'a.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Delta path = 1 get for the affected item only (refetch would
      // be 4).
      verify(() => atClient.get(any())).called(1);
      await sub.cancel();
    });

    test(
        'delta path: a delete event removes from cache with zero reads '
        '(purely cache-local)', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d2),
      });
      final q = c.query();
      final snapshots = <List<CItem<Task>>>[];
      final sub = q.watch().listen(snapshots.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.last.map((i) => i.id).toSet(), {'a', 'b'});
      clearInteractions(atClient);
      notifStream.add(objNotif(
        key: 'a.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'delete',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Delete path is purely in-memory: zero gets, zero scans.
      verifyNever(() => atClient.get(any()));
      verifyNever(() => atClient.getAtKeys(regex: any(named: 'regex')));
      expect(snapshots.last.map((i) => i.id), ['b']);
      await sub.cancel();
    });

    test(
        'delta path: an update for an item that no longer matches '
        'predicates removes it from the result set', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final q = c.query().where((t) => !t.obj.done);
      final snapshots = <List<CItem<Task>>>[];
      final sub = q.watch().listen(snapshots.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.last.single.id, 'a');
      // Flip a's done flag so it no longer matches the predicate.
      seed({'a': Task('alpha', done: true, due: d1)});
      notifStream.add(objNotif(
        key: 'a.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(snapshots.last, isEmpty);
      await sub.cancel();
    });

    test(
        'limit() falls back to full refetch (one get per matching item) '
        'on each event', () async {
      // With limit set, the next-out-of-window item isn't cached, so
      // the implementation must refetch. Under refetch a 4-item seed
      // produces 4 atClient.get calls per event (one per matching
      // key); the delta path would produce just 1.
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: false, due: d2),
        'c': Task('charlie', done: false, due: d3),
        'd': Task('delta', done: false, due: d4),
      });
      final q = c.query().limit(5);
      final sub = q.watch().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      clearInteractions(atClient);
      notifStream.add(objNotif(
        key: 'a.$namespace$selfAtSignStr',
        from: selfAtSignStr,
        to: selfAtSignStr,
        operation: 'update',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Refetch reads every key in the collection.
      verify(() => atClient.get(any())).called(4);
      await sub.cancel();
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
          .get();
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
      final items = await c.query().get();
      final item = items.single;
      final receipts = c.readReceiptsFor(item);
      // It's a proper AtCollection — we can build a Query from it.
      final q = receipts.query();
      expect(q, isNotNull);
      // Sub-collection's namespace is the `__rr` form scoped to the
      // parent item id + owner.
      expect(receipts.namespace, contains(readReceiptNamespacePart));
      expect(receipts.namespace, contains(item.id));
    });

    test('CItem.receipts delegates to AtCollection.readReceiptsFor', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final item = (await c.query().get()).single;
      expect(identical(item.receipts, c.readReceiptsFor(item)), isTrue);
    });

    test('memoised per (owner, id) across calls', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      final item = (await c.query().get()).single;
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

  // ---------------------------------------------------------------------------
  group('distinct()', () {
    test('keeps first item per keyFn output, drops later duplicates', () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d1),
        'b': Task('bravo', done: true, due: d2),
        'c': Task('charlie', done: false, due: d3),
        'd': Task('delta', done: true, due: d4),
      });
      // Without orderBy, order is fetch-order; first seen per key wins.
      final ids = (await c.query().distinct<bool>((t) => t.obj.done))
          .map((i) => i.id)
          .toSet();
      // Two entries — one for `done: true`, one for `done: false`.
      expect(ids.length, 2);
    });

    test('honours orderBy/thenBy first — winner per bucket is sort-minimum',
        () async {
      final c = buildCollection();
      seed({
        'a': Task('alpha', done: false, due: d3),
        'b': Task('bravo', done: false, due: d1),
        'c': Task('charlie', done: true, due: d4),
        'd': Task('delta', done: true, due: d2),
      });
      final ids = (await c
              .query()
              .orderBy((t) => t.obj.due)
              .distinct<bool>((t) => t.obj.done))
          .map((i) => i.id)
          .toList();
      // Sorted by due: b (d1, !done), d (d2, done), a (d3, !done), c (d4, done).
      // First-seen-per-bucket -> b (false), d (true).
      expect(ids, ['b', 'd']);
    });

    test('empty result-set returns empty list', () async {
      final c = buildCollection();
      seed({});
      final list = await c.query().distinct<int>((t) => t.obj.title.length);
      expect(list, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('exists()', () {
    test('returns true for a self-owned item present in the seed', () async {
      final c = buildCollection();
      seed({'a': Task('alpha', done: false, due: d1)});
      // Materialise once so the seen-id cache is primed.
      await c.getItems();
      expect(await c.exists('a', selfAtSign), isTrue);
    });

    test('returns false for a self-owned id that does not exist', () async {
      final c = buildCollection();
      // _selfKeyExists falls back to atClient.get(); have it throw so the
      // method returns false as documented.
      when(() => atClient.get(any())).thenThrow(Exception('no such key'));
      expect(await c.exists('nope', selfAtSign), isFalse);
    });

    test('returns false for an other-owner id with no cached copy', () async {
      final c = buildCollection();
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((_) async => <AtKey>[]);
      expect(await c.exists('a', '@bob'.toAtsign()), isFalse);
    });
  });
}
