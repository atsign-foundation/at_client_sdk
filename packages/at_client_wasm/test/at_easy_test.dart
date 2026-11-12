import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/at_easy.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'at_easy_test_utils.dart';

const _day = Duration(days: 1);
const _ns = 'todos.demo';

void main() {
  setUpAll(registerEasyFallbacks);

  late FakeAtServer server;
  late FakeAtClient alice;

  setUp(() {
    server = FakeAtServer();
    alice = server.client('@alice');
  });

  tearDown(() async {
    await alice.dispose();
  });

  AtEasy easy() => AtEasy(alice.mock, app: 'demo');

  AtEasyCollection todos(AtEasy at) =>
      at.collection('todos', type: 'Todo', expiration: _day);

  Set<String> ids(Iterable<AtEasyItem> items) =>
      {for (final item in items) item.id};

  // ---------------------------------------------------------------------------
  group('namespace and registry', () {
    test('A bare name is qualified with the app and a dotted name is used raw',
        () {
      final at = easy();
      at.collection('todos', type: 'Todo', expiration: _day);
      at.collection('x.y', type: 'Todo', expiration: _day);

      verify(() => alice.mock.collection<Map<String, dynamic>>(
            'todos.demo',
            _day,
            eventSource: EventSource.data,
            writeTypeTag: 'Todo',
            cleanupOrphansOnCreation: false,
          )).called(1);
      verify(() => alice.mock.collection<Map<String, dynamic>>(
            'x.y',
            _day,
            eventSource: EventSource.data,
            writeTypeTag: 'Todo',
            cleanupOrphansOnCreation: false,
          )).called(1);
    });

    test('An empty app is refused', () {
      expect(
        () => AtEasy(alice.mock, app: ''),
        throwsArgumentError,
      );
    });

    test('A zero or negative readTimeout is refused', () {
      for (final bad in [Duration.zero, const Duration(seconds: -1)]) {
        expect(
          () => AtEasy(alice.mock, app: 'demo', readTimeout: bad),
          throwsArgumentError,
        );
      }
    });

    test('A zero or negative expiration is refused', () {
      final at = easy();
      for (final bad in [Duration.zero, const Duration(days: -1)]) {
        expect(
          () => at.collection('todos', type: 'Todo', expiration: bad),
          throwsArgumentError,
        );
      }
      verifyNever(() => alice.mock.collection<Map<String, dynamic>>(
            any(),
            any(),
            eventSource: any(named: 'eventSource'),
            writeTypeTag: any(named: 'writeTypeTag'),
            cleanupOrphansOnCreation: any(named: 'cleanupOrphansOnCreation'),
          ));
    });

    test('An empty type is refused', () {
      expect(
        () => easy().collection('todos', type: '', expiration: _day),
        throwsArgumentError,
      );
    });

    test('Reopening a namespace with a different type is refused', () {
      final at = easy();
      todos(at);
      expect(
        () => at.collection('todos', type: 'Other', expiration: _day),
        throwsStateError,
      );
    });

    test('A failed upstream open is evicted so the next call opens again',
        () async {
      final at = easy();
      alice.failNextCollection(StateError('upstream down'));

      final failing = todos(at);
      await expectLater(
        failing.create({'title': 'x'}),
        throwsStateError,
      );
      await settle();

      final fresh = todos(at);
      expect(identical(fresh, failing), isFalse);
    });

    test(
        'Reopening a namespace with the same settings returns the same collection',
        () {
      final at = easy();
      final first = todos(at);
      final second = todos(at);

      expect(identical(first, second), isTrue);
      verify(() => alice.mock.collection<Map<String, dynamic>>(
            any(),
            any(),
            eventSource: any(named: 'eventSource'),
            writeTypeTag: any(named: 'writeTypeTag'),
            cleanupOrphansOnCreation: any(named: 'cleanupOrphansOnCreation'),
          )).called(1);
    });

    test(
        'Reopening a namespace with a different expiration or eventSource is refused',
        () {
      final at = easy();
      todos(at);
      expect(
        () => at.collection('todos',
            type: 'Todo', expiration: const Duration(hours: 1)),
        throwsStateError,
      );
      expect(
        () => at.collection('todos',
            type: 'Todo', expiration: _day, eventSource: 'notifs'),
        throwsStateError,
      );
    });

    test('A bare name and its qualified form share one collection', () {
      final at = easy();
      final bare = todos(at);
      final qualified =
          at.collection('todos.demo', type: 'Todo', expiration: _day);

      expect(identical(bare, qualified), isTrue);
      verify(() => alice.mock.collection<Map<String, dynamic>>(
            any(),
            any(),
            eventSource: any(named: 'eventSource'),
            writeTypeTag: any(named: 'writeTypeTag'),
            cleanupOrphansOnCreation: any(named: 'cleanupOrphansOnCreation'),
          )).called(1);
    });

    test(
        'The qualified form of an open namespace with a different type is refused',
        () {
      final at = easy();
      todos(at);
      expect(
        () => at.collection('todos.demo', type: 'Other', expiration: _day),
        throwsStateError,
      );
    });

    test(
        'The upstream open carries writeTypeTag and neither fromJson nor typeTag',
        () {
      todos(easy());

      verify(() => alice.mock.collection<Map<String, dynamic>>(
            _ns,
            _day,
            eventSource: EventSource.data,
            fromJson: null,
            typeTag: null,
            writeTypeTag: 'Todo',
            cleanupOrphansOnCreation: false,
          )).called(1);
    });

    test(
        'Expiration is passed through and eventSource maps to the upstream EventSource',
        () {
      final at = easy();
      at.collection('a', type: 'T', expiration: const Duration(hours: 5));
      at.collection('b', type: 'T', expiration: _day, eventSource: 'both');
      at.collection('c', type: 'T', expiration: _day, eventSource: 'notifs');

      verify(() => alice.mock.collection<Map<String, dynamic>>(
            'a.demo',
            const Duration(hours: 5),
            eventSource: EventSource.data,
            writeTypeTag: 'T',
            cleanupOrphansOnCreation: false,
          )).called(1);
      verify(() => alice.mock.collection<Map<String, dynamic>>(
            'b.demo',
            _day,
            eventSource: EventSource.both,
            writeTypeTag: 'T',
            cleanupOrphansOnCreation: false,
          )).called(1);
      verify(() => alice.mock.collection<Map<String, dynamic>>(
            'c.demo',
            _day,
            eventSource: EventSource.notifs,
            writeTypeTag: 'T',
            cleanupOrphansOnCreation: false,
          )).called(1);
    });

    test('An unknown eventSource is refused', () {
      expect(
        () => easy().collection('todos',
            type: 'Todo', expiration: _day, eventSource: 'bogus'),
        throwsArgumentError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('items', () {
    test('A create returns the item with its data, owner, type and no sharing',
        () async {
      final coll = todos(easy());
      final item = await coll.create({'title': 'a', 'done': false}, id: 'i1');

      expect(item.id, 'i1');
      expect(item.data, {'title': 'a', 'done': false});
      expect(item.owner, '@alice');
      expect(item.type, 'Todo');
      expect(item.sharedWith, isEmpty);
      expect(item.ancestors, isEmpty);
    });

    test('An update replaces the data and a missing id is refused', () async {
      final coll = todos(easy());
      await coll.create({'title': 'a'}, id: 'i1');

      final updated = await coll.update('i1', {'title': 'b'});
      expect(updated.data, {'title': 'b'});

      final fetched = await coll.get();
      expect(fetched.single.data, {'title': 'b'});

      await expectLater(
        coll.update('nope', {'title': 'x'}),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('no item nope'))),
      );
    });

    test('An update ignores an unreadable peer item that shares the id',
        () async {
      final bob = server.client('@bob');
      await rawCollection(bob, _ns, writeTypeTag: 'Todo').create(
        obj: {'title': 'bob'},
        id: 'a1',
        sharedWith: {'@alice'.toAtsign()},
      );
      server.overwriteValues(
        (key) =>
            key.sharedBy?.toAtsign() == '@bob'.toAtsign() &&
            key.sharedWith?.toAtsign() == '@alice'.toAtsign(),
        'not json',
      );
      final coll = todos(easy());
      await coll.create({'title': 'mine'}, id: 'a1');

      final updated = await coll.update('a1', {'title': 'changed'});

      expect(updated.owner, '@alice');
      expect(updated.data, {'title': 'changed'});
    });

    test('An update keeps sharedWith', () async {
      final coll = todos(easy());
      await coll.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']);

      await coll.update('i1', {'title': 'b'});

      final fetched = await coll.get();
      expect(fetched.single.data, {'title': 'b'});
      expect(fetched.single.sharedWith, contains('@bob'));
    });

    test(
        'An update keeps expiresAt and leaves an available item without availableAt',
        () async {
      final coll = todos(easy());
      final raw = rawCollection(alice, _ns, writeTypeTag: 'Todo');
      final expiresAt = DateTime.now().toUtc().add(const Duration(days: 3));
      await raw.create(obj: {'title': 'a'}, id: 'i1', expiresAt: expiresAt);
      final before = (await coll.get()).single;
      expect(before.availableAt, isNull);

      final updated = await coll.update('i1', {'title': 'b'});

      expect(updated.expiresAt, before.expiresAt);
      expect(updated.availableAt, isNull);
      final fetched = (await coll.get()).single;
      expect(fetched.data, {'title': 'b'});
      expect(fetched.expiresAt, before.expiresAt);
      expect(fetched.expiresAt.difference(expiresAt).abs(),
          lessThan(const Duration(seconds: 1)));
      expect(fetched.availableAt, isNull);
    });

    test('An update re-stamps a legacy untagged item with the declared type',
        () async {
      final coll = todos(easy());
      await rawCollection(alice, _ns).create(obj: {'title': 'old'}, id: 'n1');
      expect((await coll.get()).single.type, 'n/a');

      final updated = await coll.update('n1', {'title': 'new'});

      expect(updated.type, 'Todo');
      final fetched = (await coll.get()).single;
      expect(fetched.type, 'Todo');
      expect(fetched.data, {'title': 'new'});
    });

    test(
        'An update of an id whose only item is an unreadable peer item is refused',
        () async {
      final bob = server.client('@bob');
      await rawCollection(bob, _ns, writeTypeTag: 'Todo').create(
        obj: {'title': 'bob'},
        id: 'b1',
        sharedWith: {'@alice'.toAtsign()},
      );
      server.overwriteValues(
        (key) =>
            key.sharedBy?.toAtsign() == '@bob'.toAtsign() &&
            key.sharedWith?.toAtsign() == '@alice'.toAtsign(),
        'not json',
      );
      final coll = todos(easy());

      await expectLater(
        coll.update('b1', {'title': 'mine'}),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', startsWith('no item '))),
      );
    });

    test('An update or remove of another owner\'s item names the owner',
        () async {
      final bob = server.client('@bob');
      await rawCollection(bob, _ns, writeTypeTag: 'Todo').create(
        obj: {'title': 'bob'},
        id: 'b1',
        sharedWith: {'@alice'.toAtsign()},
      );
      final coll = todos(easy());

      await expectLater(
        coll.update('b1', {'title': 'mine'}),
        throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(
                'item b1 is owned by @bob; only the owner can change it'))),
      );
      await expectLater(
        coll.remove('b1'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('owned by @bob'))),
      );
    });

    test('A share adds recipients, keeps existing ones and normalises names',
        () async {
      final coll = todos(easy());
      await coll.create({'title': 'a'},
          id: 'i1', sharedWith: {'@carol'.toAtsign()});

      final shared = await coll.share('i1', ['bob']);

      expect(shared.sharedWith, {'@carol', '@bob'});
      final fetched = await coll.get();
      expect(fetched.single.sharedWith, {'@carol', '@bob'});
    });

    test('A remove deletes the item and a missing id is refused', () async {
      final coll = todos(easy());
      await coll.create({'title': 'a'}, id: 'i1');

      await coll.remove('i1');
      expect(await coll.get(), isEmpty);

      await expectLater(
        coll.remove('i1'),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('no item i1'))),
      );
    });

    test('A remove of a parent with a child needs cascade', () async {
      final coll = todos(easy());
      await coll.create({'title': 'p'}, id: 'p1');

      final raw = rawCollection(alice, _ns, writeTypeTag: 'Todo');
      final parent = await raw.get('p1', alice.atSign);
      final notes = raw.subCollection<Map<String, dynamic>>(
        parent: parent,
        subName: 'notes',
        defaultExpiration: _day,
        writeTypeTag: 'Note',
      );
      await notes.create(obj: {'text': 'child'}, id: 'n1');

      await expectLater(coll.remove('p1'), throwsStateError);
      await coll.remove('p1', cascade: true);

      expect(await notes.getItems(), isEmpty);
      expect(await coll.get(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('where, order and limit', () {
    Future<void> seedFlags(AtEasyCollection coll) async {
      await coll.create({
        'done': false,
        'prio': 1,
        'meta': {'prio': 2}
      }, id: 'a');
      await coll.create({
        'done': true,
        'prio': 5,
        'meta': {'prio': 7}
      }, id: 'b');
      await coll.create({'done': false, 'prio': null}, id: 'c');
    }

    test('Each where operator works on nested and missing paths', () async {
      final coll = todos(easy());
      await seedFlags(coll);

      expect(ids(await coll.where('done', '==', false).get()), {'a', 'c'});
      expect(ids(await coll.where('done', '!=', false).get()), {'b'});
      expect(ids(await coll.where('prio', '<', 5).get()), {'a'});
      expect(ids(await coll.where('prio', '<=', 5).get()), {'a', 'b'});
      expect(ids(await coll.where('prio', '>', 1).get()), {'b'});
      expect(ids(await coll.where('prio', '>=', 5).get()), {'b'});
      expect(ids(await coll.where('prio', 'isNull', null).get()), {'c'});
      expect(
          ids(await coll.where('prio', 'isNotNull', null).get()), {'a', 'b'});
      expect(ids(await coll.where('meta.prio', '>=', 7).get()), {'b'});
      expect(ids(await coll.where('meta.prio', '==', 2).get()), {'a'});
      expect(
          ids(await coll.where('nope', 'isNull', null).get()), {'a', 'b', 'c'});
    });

    test('Chained where clauses combine with AND', () async {
      final coll = todos(easy());
      await seedFlags(coll);

      final both = coll.where('done', '==', false).where('prio', '>', 0);
      expect(ids(await both.get()), {'a'});
    });

    test('A where on mixed types excludes them and rejects map values',
        () async {
      final coll = todos(easy());
      await coll.create({'prio': 1}, id: 'n1');
      await coll.create({'prio': 'high'}, id: 'h');
      await coll.create({'prio': null}, id: 'z');
      await coll.create({'prio': true}, id: 't');
      await coll.create({
        'prio': <String, dynamic>{'x': 1}
      }, id: 'm');

      expect(ids(await coll.where('prio', '<', 5).get()), {'n1'});
      expect(ids(await coll.where('prio', '<', 'm').get()), {'h'});
      expect(
        () => coll.where('prio', '==', <String, dynamic>{}),
        throwsArgumentError,
      );
    });

    test('An unknown where operator is refused by name', () {
      final coll = todos(easy());
      expect(
        () => coll.where('x', 'like', 'a%'),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', contains('like'))),
      );
      expect(
        () => coll.where('x', '~', 1),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', contains('~'))),
      );
    });

    test(
        'An ordered query with a limit returns the first items in either direction',
        () async {
      final coll = todos(easy());
      await coll.create({'due': 3}, id: 'x1');
      await coll.create({'due': 1}, id: 'x2');
      await coll.create({'due': 2}, id: 'x3');

      final asc = await coll.orderByPath('due').limit(2).get();
      expect(asc.map((i) => i.id).toList(), ['x2', 'x3']);

      final desc =
          await coll.orderByPath('due', descending: true).limit(2).get();
      expect(desc.map((i) => i.id).toList(), ['x1', 'x3']);
    });

    test('A query skips an unreadable peer record', () async {
      final coll = todos(easy());
      await coll.create({'due': 3}, id: 'a1');
      final bob = server.client('@bob');
      final bobColl = rawCollection(bob, _ns, writeTypeTag: 'Todo');
      for (final (id, due) in [('b1', 1), ('b2', 2), ('b3', 4)]) {
        await bobColl.create(
          obj: {'due': due},
          id: id,
          sharedWith: {'@alice'.toAtsign()},
        );
      }
      server.overwriteValues(
        (key) =>
            key.sharedBy?.toAtsign() == '@bob'.toAtsign() &&
            key.toString().contains('b2'),
        'not json',
      );

      final all = await coll.get();
      final top = await coll
          .where('due', '>=', 1)
          .orderByPath('due', descending: true)
          .limit(2)
          .get();

      expect(ids(all), {'a1', 'b1', 'b3'});
      expect(top.map((i) => i.id).toList(), ['b3', 'a1']);
    });

    test('Mixed values sort in a total order with an id tie-break', () async {
      final coll = todos(easy());
      await coll.create({'due': null}, id: 'n');
      await coll.create({'due': false}, id: 'f');
      await coll.create({'due': 1}, id: 'one');
      await coll.create({'due': 3}, id: 'b3');
      await coll.create({'due': 3}, id: 'a3');
      await coll.create({'due': 'a'}, id: 'sa');
      await coll.create({'due': 'b'}, id: 'sb');
      await coll.create({'due': <String, dynamic>{}}, id: 'mp');

      const asc = ['n', 'f', 'one', 'a3', 'b3', 'sa', 'sb', 'mp'];
      final first = await coll.orderByPath('due').get();
      expect(first.map((i) => i.id).toList(), asc);

      final second = await coll.orderByPath('due').get();
      expect(second.map((i) => i.id).toList(), asc);

      final desc = await coll.orderByPath('due', descending: true).get();
      expect(desc.map((i) => i.id).toList(), asc.reversed.toList());
    });
  });

  // ---------------------------------------------------------------------------
  group('type filter', () {
    test(
        'Items tagged with another type are hidden and untagged items are kept',
        () async {
      final coll = todos(easy());
      await coll.create({'title': 'mine'}, id: 't1');
      await rawCollection(alice, _ns)
          .create(obj: {'title': 'untagged'}, id: 'n1');
      await rawCollection(alice, _ns, writeTypeTag: 'Other')
          .create(obj: {'title': 'other'}, id: 'o1');

      final fetched = await coll.get();
      expect(ids(fetched), {'t1', 'n1'});
      expect(fetched.firstWhere((i) => i.id == 'n1').type, 'n/a');
    });

    test('An item tagged with another type cannot be updated', () async {
      final coll = todos(easy());
      await rawCollection(alice, _ns, writeTypeTag: 'Other')
          .create(obj: {'title': 'other'}, id: 'o1');

      await expectLater(
        coll.update('o1', {'title': 'x'}),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('no item o1'))),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('watch', () {
    test('Each upstream change is delivered once and cancel stops delivery',
        () async {
      final coll = todos(easy());
      await coll.create({'title': 'a'}, id: 't1');
      final events = <AtEasyEvent>[];

      final cancel = coll.watch(events.add);
      await settle();

      alice.dataEvents
          .add(DataUpdated(AtKey.fromString('t1.todos.demo@alice')));
      await settle();
      alice.dataEvents
          .add(DataDeleted(AtKey.fromString('t1.todos.demo@alice')));
      await settle();

      expect(events.map((e) => e.kind).toList(), ['updated', 'deleted']);
      expect(events.first.item?.data, {'title': 'a'});
      expect(events.first.id, 't1');
      expect(events.first.owner, '@alice');
      expect(events.last.item, isNull);

      cancel();
      await settle();
      alice.dataEvents
          .add(DataUpdated(AtKey.fromString('t1.todos.demo@alice')));
      await settle();

      expect(events, hasLength(2));
    });

    test('An unreadable peer record is delivered with a null item and no error',
        () async {
      final coll = todos(easy());
      final bob = server.client('@bob');
      await rawCollection(bob, _ns, writeTypeTag: 'Todo').create(
        obj: {'title': 'bob'},
        id: 'b1',
        sharedWith: {'@alice'.toAtsign()},
      );
      server.overwriteValues(
        (key) =>
            key.sharedBy?.toAtsign() == '@bob'.toAtsign() &&
            key.sharedWith?.toAtsign() == '@alice'.toAtsign(),
        'not json',
      );
      final events = <AtEasyEvent>[];
      final errors = <Object>[];

      final cancel = coll.watch(events.add, onError: errors.add);
      await settle();

      alice.dataEvents.add(DataUpdated(AtKey.fromString('b1.todos.demo@bob')));
      await settle();

      expect(errors, isEmpty);
      expect(events.map((e) => e.kind).toList(), ['updated']);
      expect(events.single.id, 'b1');
      expect(events.single.owner, '@bob');
      expect(events.single.item, isNull);

      cancel();
    });

    test(
        'An error while handling an event goes to onError and later events still arrive',
        () async {
      final coll = todos(easy());
      await coll.create({'title': 'a'}, id: 't1');
      final events = <AtEasyEvent>[];
      final errors = <Object>[];

      final cancel = coll.watch(events.add, onError: errors.add);
      await settle();

      alice.failNextGetAtKeys(StateError('keystore down'));
      alice.dataEvents
          .add(DataUpdated(AtKey.fromString('t1.todos.demo@alice')));
      await settle();
      alice.dataEvents
          .add(DataUpdated(AtKey.fromString('t1.todos.demo@alice')));
      await settle();

      expect(errors.single, isA<StateError>());
      expect(events.map((e) => e.kind).toList(), ['updated']);
      expect(events.single.item?.data, {'title': 'a'});

      cancel();
    });

    test(
        'A watch read that never completes is delivered with a null item after the read timeout',
        () async {
      final events = <AtEasyEvent>[];
      final errors = <Object>[];

      fakeAsync((async) {
        final coll = todos(AtEasy(alice.mock,
            app: 'demo', readTimeout: const Duration(milliseconds: 50)));
        coll.create({'title': 'a'}, id: 't1');
        async.flushMicrotasks();
        alice.hangGetsFor((_) => true);

        final cancel = coll.watch(events.add, onError: errors.add);
        async.elapse(Duration.zero);

        alice.dataEvents
            .add(DataUpdated(AtKey.fromString('t1.todos.demo@alice')));
        async.elapse(Duration.zero);
        expect(events, isEmpty);

        async.elapse(const Duration(milliseconds: 49));
        expect(events, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        expect(errors, isEmpty);
        expect(events.map((e) => e.kind).toList(), ['updated']);
        expect(events.single.id, 't1');
        expect(events.single.item, isNull);

        cancel();
      });
    });

    test(
        'A watch error with no onError reaches the zone and later events still arrive',
        () async {
      final coll = todos(easy());
      await coll.create({'title': 'a'}, id: 't1');
      final events = <AtEasyEvent>[];
      final zoneErrors = <Object>[];
      late void Function() cancel;

      await runZonedGuarded(() async {
        cancel = coll.watch(events.add);
        await settle();

        alice.failNextGetAtKeys(StateError('keystore down'));
        alice.dataEvents
            .add(DataUpdated(AtKey.fromString('t1.todos.demo@alice')));
        await settle();
        alice.dataEvents
            .add(DataUpdated(AtKey.fromString('t1.todos.demo@alice')));
        await settle();
      }, (error, _) => zoneErrors.add(error));

      expect(zoneErrors.single, isA<StateError>());
      expect(events.map((e) => e.kind).toList(), ['updated']);
      expect(events.single.item?.data, {'title': 'a'});

      cancel();
    });

    test(
        'Id-only events pass the type filter and a foreign-tag update is dropped',
        () async {
      final coll = todos(easy());
      await rawCollection(alice, _ns, writeTypeTag: 'Other')
          .create(obj: {'title': 'other'}, id: 'o1');
      final events = <AtEasyEvent>[];

      final cancel = coll.watch(events.add);
      await settle();

      alice.dataEvents
          .add(DataUpdated(AtKey.fromString('o1.todos.demo@alice')));
      await settle();
      alice.dataEvents.add(DataDeleted(
        AtKey.fromString('o1.todos.demo@alice'),
        wasExpired: true,
      ));
      await settle();
      alice.dataEvents
          .add(DataUpdated(AtKey.fromString('gone.todos.demo@alice')));
      await settle();

      expect(events.map((e) => e.kind).toList(), ['deleted', 'updated']);
      expect(events.map((e) => e.id).toList(), ['o1', 'gone']);
      expect(events.map((e) => e.owner).toSet(), {'@alice'});
      expect(events.every((e) => e.item == null), isTrue);

      cancel();
    });
  });

  // ---------------------------------------------------------------------------
  group('structure', () {
    test('The facade and its package-local imports reach no web-only API',
        () async {
      final root = await Isolate.resolvePackageUri(
        Uri.parse('package:at_client_wasm/at_easy.dart'),
      );
      expect(root, isNotNull);
      final libDir = root!.resolve('.');
      final rootPath = root.toFilePath();

      final visited = <String>{};
      final pending = [rootPath];
      final importPattern = RegExp(
        r"^\s*(?:import|export)\s+'([^']+)'",
        multiLine: true,
      );

      while (pending.isNotEmpty) {
        final path = pending.removeLast();
        if (!visited.add(path)) continue;
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('dart:js_interop')), reason: path);
        expect(source, isNot(contains('package:web')), reason: path);
        for (final match in importPattern.allMatches(source)) {
          final target = match.group(1)!;
          if (target.startsWith('package:at_client_wasm/')) {
            pending.add(libDir
                .resolve(target.substring('package:at_client_wasm/'.length))
                .toFilePath());
          } else if (!target.contains(':')) {
            pending.add(File(path).parent.uri.resolve(target).toFilePath());
          }
        }
      }

      expect(visited, contains(rootPath));
    });
  });
}
