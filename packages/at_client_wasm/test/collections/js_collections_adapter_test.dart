// Scenarios: features/at_client_wasm/js_collections_adapter.feature. Each
// test is named after its scenario.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:at_client/at_client.dart';
import 'package:at_client_wasm/src/collections/js_collections_adapter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'adapter_test_utils.dart';

const _ns = 'todos.demo';
const _day = Duration(days: 1);

/// A CEvent subtype the adapter does not know, standing in for one a later
/// at_client adds.
final class _LaterEvent extends CEvent {
  _LaterEvent() : super(owner: '@alice'.toAtsign(), id: 'later');
}

Matcher _rejectsWith(String code, {String? id, String? owner, String? kind}) =>
    throwsA(isA<JsCollectionsError>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.id, 'id', id ?? anything)
        .having((e) => e.owner, 'owner', owner ?? anything)
        .having((e) => e.kind, 'kind', kind ?? anything));

void main() {
  setUpAll(registerAdapterFallbacks);

  late FakeAtServer server;
  late FakeAtClient alice;

  setUp(() {
    server = FakeAtServer();
    alice = server.client('@alice');
  });

  tearDown(() async {
    await alice.dispose();
  });

  Future<JsCollectionsAdapter> open({String type = 'Todo'}) =>
      JsCollectionsAdapter.open(alice.mock,
          namespace: _ns, type: type, expirationMs: _day.inMilliseconds);

  JsItemAddress mine(String id) => (id: id, owner: '@alice');
  JsItemAddress bobs(String id) => (id: id, owner: '@bob');

  List<String> ids(List<JsItem> items) =>
      [for (final item in items) item['id'] as String];

  /// @bob writes [id], shared with @alice, and makes @alice's copy of it
  /// unreadable.
  Future<void> bobSharesUnreadable(String id) async {
    final bob = server.client('@bob');
    await rawCollection(bob, _ns, writeTypeTag: 'Todo').create(
      obj: {'title': 'bob'},
      id: id,
      sharedWith: {'@alice'.toAtsign()},
    );
    server.overwriteValues(
      (key) =>
          key.sharedBy?.toAtsign() == '@bob'.toAtsign() &&
          key.sharedWith?.toAtsign() == '@alice'.toAtsign(),
      'not json',
    );
  }

  Future<void> bobShares(String id, Map<String, dynamic> obj) async {
    final bob = server.client('@bob');
    await rawCollection(bob, _ns, writeTypeTag: 'Todo').create(
      obj: obj,
      id: id,
      sharedWith: {'@alice'.toAtsign()},
    );
  }

  // ---------------------------------------------------------------------------
  group('open', () {
    test(
        'An open passes namespace, expiration, type and eventSource through unchanged',
        () async {
      const hours5 = Duration(hours: 5);
      for (final source in ['data', 'notifs', 'both']) {
        await JsCollectionsAdapter.open(alice.mock,
            namespace: _ns,
            type: 'Todo',
            expirationMs: hours5.inMilliseconds,
            eventSource: source);
      }
      await JsCollectionsAdapter.open(alice.mock,
          namespace: 'notes.demo',
          type: 'Note',
          expirationMs: _day.inMilliseconds);

      for (final source in EventSource.values) {
        verify(() => alice.mock.collection<Map<String, dynamic>>(
              _ns,
              hours5,
              eventSource: source,
              fromJson: null,
              typeTag: null,
              writeTypeTag: 'Todo',
              cleanupOrphansOnCreation: false,
            )).called(1);
      }
      verify(() => alice.mock.collection<Map<String, dynamic>>(
            'notes.demo',
            _day,
            eventSource: EventSource.both,
            fromJson: null,
            typeTag: null,
            writeTypeTag: 'Note',
            cleanupOrphansOnCreation: false,
          )).called(1);
    });

    test('An unknown eventSource rejects with W8_INVALID_ARGUMENT', () async {
      await expectLater(
        JsCollectionsAdapter.open(alice.mock,
            namespace: _ns,
            type: 'Todo',
            expirationMs: _day.inMilliseconds,
            eventSource: 'bogus'),
        _rejectsWith(W8.invalidArgument),
      );
    });

    test('An empty type rejects with W8_INVALID_ARGUMENT', () async {
      await expectLater(open(type: ''), _rejectsWith(W8.invalidArgument));
    });

    test('A failed open rejects with W8_FAILED naming the error kind',
        () async {
      alice.failNextCollection(StateError('upstream down'));

      await expectLater(open(), _rejectsWith(W8.failed, kind: 'StateError'));
    });

    test(
        'A record written through the adapter carries its declared type tag on the wire',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1');

      final stored = server.storedValue('i1.$_ns@alice');
      expect(stored, isNotNull);
      expect((jsonDecode(stored!) as Map<String, dynamic>)['type'], 'Todo');
    });
  });

  // ---------------------------------------------------------------------------
  group('items', () {
    test('A create returns the item with id, owner, type, data and sharedWith',
        () async {
      final todos = await open();

      final item =
          await todos.create({'title': 'a'}, id: 'i1', sharedWith: ['bob']);

      expect(item['id'], 'i1');
      expect(item['owner'], '@alice');
      expect(item['type'], 'Todo');
      expect(item['data'], {'title': 'a'});
      expect(item['sharedWith'], ['@bob']);
      expect(item['expiresAt'], isA<int>());
      expect(item['createdAt'], isA<int>());
      expect(item['availableAt'], isNull);
    });

    test('A create with an existing id rejects with W8_ALREADY_EXISTS',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1');

      await expectLater(
        todos.create({'title': 'b'}, id: 'i1'),
        _rejectsWith(W8.alreadyExists),
      );
    });

    test('A get addresses an item by id and owner', () async {
      await bobShares('a1', {'title': 'bob'});
      final todos = await open();
      await todos.create({'title': 'mine'}, id: 'a1');

      final theirs = await todos.get(bobs('a1'));
      final ours = await todos.get(mine('a1'));

      expect(theirs?['owner'], '@bob');
      expect(theirs?['data'], {'title': 'bob'});
      expect(ours?['owner'], '@alice');
      expect(ours?['data'], {'title': 'mine'});
      expect(await todos.get(mine('nope')), isNull);
    });

    test(
        'A get of an unreadable item rejects with W8_UNREADABLE naming id and owner',
        () async {
      await bobSharesUnreadable('b1');
      final todos = await open();

      await expectLater(
        todos.get(bobs('b1')),
        throwsA(isA<JsCollectionsError>()
            .having((e) => e.code, 'code', W8.unreadable)
            .having((e) => e.id, 'id', 'b1')
            .having((e) => e.owner, 'owner', '@bob')
            .having((e) => e.message, 'message', isNot(contains('json')))
            .having((e) => e.message, 'message',
                isNot(contains('FormatException')))),
      );
    });

    test('A list rejects with W8_UNREADABLE when one record is unreadable',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'a1');
      await bobSharesUnreadable('b1');

      await expectLater(
        todos.list(),
        _rejectsWith(W8.unreadable, id: 'b1', owner: '@bob'),
      );
    });

    test('A list keeps the upstream order of items and recipients', () async {
      final todos = await open();
      // AtCollection lists by key, so 'a-b' ('a-b.todos…') comes before
      // 'a' ('a.todos…'): neither creation order nor id order.
      const created = ['c', 'a', 'a-b'];
      for (final id in created) {
        await todos.create({'title': id}, id: id, sharedWith: ['@zed', '@amy']);
      }

      final listed = await todos.list();
      final upstream = await rawCollection(alice, _ns).getItems();

      expect(ids(listed), [for (final item in upstream) item.id]);
      expect(ids(listed), isNot(orderedEquals(created)));
      expect(ids(listed), isNot(orderedEquals([...created]..sort())));
      expect(ids(listed),
          isNot(orderedEquals([...created]..sort((a, b) => b.compareTo(a)))));
      for (final (i, item) in listed.indexed) {
        expect(item['sharedWith'], upstream[i].sharedWith.toList());
      }
      expect(listed.first['sharedWith'], ['@zed', '@amy']);
    });

    test('Items of every type tag are listed with their type', () async {
      final todos = await open();
      await todos.create({'title': 'mine'}, id: 't1');
      await rawCollection(alice, _ns, writeTypeTag: 'Other')
          .create(obj: {'title': 'other'}, id: 'o1');
      await rawCollection(alice, _ns)
          .create(obj: {'title': 'untagged'}, id: 'n1');

      final types = {
        for (final item in await todos.list()) item['id']: item['type']
      };

      expect(types, {'t1': 'Todo', 'o1': 'Other', 'n1': 'n/a'});
    });

    test(
        'An update replaces the data and keeps sharedWith, expiresAt and availableAt',
        () async {
      final todos = await open();
      await rawCollection(alice, _ns, writeTypeTag: 'Todo').create(
        obj: {'title': 'a'},
        id: 'i1',
        sharedWith: {'@bob'.toAtsign()},
        expiresAt: DateTime.utc(2100),
        availableAt: DateTime.utc(2000),
      );
      final before = (await todos.get(mine('i1')))!;

      final updated = await todos.update(mine('i1'), {'title': 'b'});
      final after = (await todos.get(mine('i1')))!;

      for (final item in [updated, after]) {
        expect(item['data'], {'title': 'b'});
        expect(item['sharedWith'], ['@bob']);
        expect(item['expiresAt'], DateTime.utc(2100).millisecondsSinceEpoch);
        expect(item['availableAt'], before['availableAt']);
      }
      expect(before['data'], {'title': 'a'});
      expect(server.hasKey('@bob:i1.$_ns@alice'), isTrue);
    });

    test('An update of a missing item rejects with W8_NOT_FOUND', () async {
      final todos = await open();

      await expectLater(
        todos.update(mine('nope'), {'title': 'x'}),
        _rejectsWith(W8.notFound, id: 'nope', owner: '@alice'),
      );
    });

    test(
        "An update, share or remove of another owner's item rejects with W8_NOT_OWNER",
        () async {
      await bobShares('b1', {'title': 'bob'});
      final todos = await open();

      await expectLater(todos.update(bobs('b1'), {'title': 'mine'}),
          _rejectsWith(W8.notOwner, id: 'b1', owner: '@bob'));
      await expectLater(todos.share(bobs('b1'), ['@carol']),
          _rejectsWith(W8.notOwner, id: 'b1', owner: '@bob'));
      await expectLater(todos.remove(bobs('b1')),
          _rejectsWith(W8.notOwner, id: 'b1', owner: '@bob'));

      expect(server.hasKey('b1.$_ns@alice'), isFalse);
      expect((await todos.get(bobs('b1')))?['data'], {'title': 'bob'});
    });

    test(
        "An update addresses the owner's own item when an unreadable peer item shares the id",
        () async {
      await bobSharesUnreadable('a1');
      final todos = await open();
      await todos.create({'title': 'mine'}, id: 'a1');

      final updated = await todos.update(mine('a1'), {'title': 'changed'});

      expect(updated['owner'], '@alice');
      expect(updated['data'], {'title': 'changed'});
      expect((await todos.get(mine('a1')))?['data'], {'title': 'changed'});
    });

    test(
        'An update keeps a recipient copy another device writes during the update',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']);
      alice.beforeNextPut(
        (key) => key.toString() == 'i1.$_ns@alice',
        () => server.putRaw('@carol:i1.$_ns@alice', '{}'),
      );

      await todos.update(mine('i1'), {'title': 'b'});

      expect(server.hasKey('@carol:i1.$_ns@alice'), isTrue);
      expect(server.hasKey('@bob:i1.$_ns@alice'), isTrue);
    });

    test('A share adds recipients and keeps existing ones', () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@carol']);

      final shared = await todos.share(mine('i1'), ['bob']);

      expect(shared['sharedWith'], unorderedEquals(['@carol', '@bob']));
      expect((await todos.get(mine('i1')))?['sharedWith'],
          unorderedEquals(['@carol', '@bob']));
      expect(server.hasKey('@carol:i1.$_ns@alice'), isTrue);
      expect(server.hasKey('@bob:i1.$_ns@alice'), isTrue);
    });

    test(
        'A share keeps a recipient copy another device writes during the share',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']);
      alice.beforeNextPut(
        (key) => key.toString().endsWith('i1.$_ns@alice'),
        () => server.putRaw('@carol:i1.$_ns@alice', '{}'),
      );

      await todos.share(mine('i1'), ['@dave']);

      expect(server.hasKey('@carol:i1.$_ns@alice'), isTrue);
      expect(server.hasKey('@bob:i1.$_ns@alice'), isTrue);
      expect(server.hasKey('@dave:i1.$_ns@alice'), isTrue);
    });

    test('A share of a missing item rejects with W8_NOT_FOUND', () async {
      final todos = await open();

      await expectLater(
        todos.share(mine('nope'), ['@bob']),
        _rejectsWith(W8.notFound, id: 'nope', owner: '@alice'),
      );
    });

    test('A share with an invalid atSign rejects with W8_INVALID_ARGUMENT',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']);

      await expectLater(
        todos.share(mine('i1'), ['@a@b']),
        _rejectsWith(W8.invalidArgument),
      );
      expect((await todos.get(mine('i1')))?['sharedWith'], ['@bob']);
    });

    test(
        'A partial write failure rejects with W8_PARTIAL_FAILURE naming the recipient',
        () async {
      final todos = await open();
      alice.failPutsFor((key) => key.sharedWith?.toAtsign() == '@bob');

      await expectLater(
        todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']),
        throwsA(isA<JsCollectionsError>()
            .having((e) => e.code, 'code', W8.partialFailure)
            .having((e) => e.failures, 'failures', [
          {'op': 'put', 'recipient': '@bob', 'kind': 'AtClientException'}
        ])),
      );
    });

    test(
        'A remove deletes the item and a missing item rejects with W8_NOT_FOUND',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1');

      await todos.remove(mine('i1'));

      expect(await todos.get(mine('i1')), isNull);
      await expectLater(
        todos.remove(mine('i1')),
        _rejectsWith(W8.notFound, id: 'i1', owner: '@alice'),
      );
    });

    test(
        'A remove of an item with sub-items rejects with W8_HAS_SUB_ITEMS unless cascade',
        () async {
      final todos = await open();
      await todos.create({'title': 'p'}, id: 'p1');
      final raw = rawCollection(alice, _ns, writeTypeTag: 'Todo');
      final notes = raw.subCollection<Map<String, dynamic>>(
        parent: await raw.get('p1', alice.atSign),
        subName: 'notes',
        defaultExpiration: _day,
        writeTypeTag: 'Note',
      );
      await notes.create(obj: {'text': 'child'}, id: 'n1');

      await expectLater(
        todos.remove(mine('p1')),
        _rejectsWith(W8.hasSubItems, id: 'p1', owner: '@alice'),
      );
      expect(await todos.get(mine('p1')), isNotNull);

      await todos.remove(mine('p1'), cascade: true);

      expect(await todos.get(mine('p1')), isNull);
      expect(await notes.getItems(), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('query', () {
    Future<JsCollectionsAdapter> seeded() async {
      final todos = await open();
      await todos.create({
        'done': false,
        'prio': 1,
        'meta': {'prio': 2}
      }, id: 'a');
      await todos.create({
        'done': true,
        'prio': 5,
        'meta': {'prio': 7}
      }, id: 'b');
      await todos.create({'done': false, 'prio': null}, id: 'c');
      return todos;
    }

    Future<Set<String>> where(JsCollectionsAdapter todos, String path,
            String op, Object? value) async =>
        ids(await todos.query([(path: path, op: op, value: value)])).toSet();

    test(
        'Each where operator maps onto wherePath over nested and missing paths',
        () async {
      final todos = await seeded();

      expect(await where(todos, 'done', '==', false), {'a', 'c'});
      expect(await where(todos, 'done', '!=', false), {'b'});
      expect(await where(todos, 'prio', '<', 5), {'a'});
      expect(await where(todos, 'prio', '<=', 5), {'a', 'b'});
      expect(await where(todos, 'prio', '>', 1), {'b'});
      expect(await where(todos, 'prio', '>=', 5), {'b'});
      expect(await where(todos, 'prio', 'isNull', null), {'c'});
      expect(await where(todos, 'prio', 'isNotNull', null), {'a', 'b'});
      expect(await where(todos, 'meta.prio', '>=', 7), {'b'});
      expect(await where(todos, 'meta.prio', '==', 2), {'a'});
      expect(await where(todos, 'nope', 'isNull', null), {'a', 'b', 'c'});
      expect(
          await where(todos, 'done.deeper', 'isNull', null), {'a', 'b', 'c'});
    });

    test('Chained where clauses combine with AND', () async {
      final todos = await seeded();

      final both = await todos.query([
        (path: 'done', op: '==', value: false),
        (path: 'prio', op: '>', value: 0),
      ]);

      expect(ids(both), ['a']);
    });

    test('An ordering where over mixed types rejects with W8_TYPE_MISMATCH',
        () async {
      final todos = await open();
      await todos.create({'prio': 1}, id: 'n1');
      await todos.create({'prio': 'high'}, id: 'h');
      await todos.create({'prio': true}, id: 't');

      await expectLater(
        todos.query([(path: 'prio', op: '<', value: 5)]),
        _rejectsWith(W8.typeMismatch),
      );
    });

    test(
        'An unknown or reserved operator or a bad path or value rejects with W8_INVALID_ARGUMENT',
        () async {
      final todos = await seeded();
      Matcher naming(String text) => throwsA(isA<JsCollectionsError>()
          .having((e) => e.code, 'code', W8.invalidArgument)
          .having((e) => e.message, 'message', contains(text)));

      await expectLater(
          todos.query([(path: 'x', op: 'like', value: 'a%')]), naming('like'));
      await expectLater(
          todos.query([(path: 'x', op: '~', value: 1)]), naming('~'));
      await expectLater(
          todos.query([(path: 'x', op: '=<', value: <String, dynamic>{})]),
          naming('unknown where operator "=<"'));
      await expectLater(todos.query([(path: 'meta..prio', op: '==', value: 1)]),
          naming('meta..prio'));
      await expectLater(
          todos.query([(path: 'prio', op: '<', value: <String, dynamic>{})]),
          naming('<'));
      await expectLater(
          todos.query([(path: 'prio', op: '>=', value: null)]), naming('>='));
    });

    test('A query rejects with W8_UNREADABLE when one record is unreadable',
        () async {
      final todos = await seeded();
      await bobSharesUnreadable('b1');

      await expectLater(
        todos.query([(path: 'done', op: '==', value: false)]),
        _rejectsWith(W8.unreadable, id: 'b1', owner: '@bob'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('watch', () {
    test('Each upstream event is delivered once and cancel stops delivery',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 't1');
      final events = <JsEvent>[];
      final errors = <JsCollectionsError>[];

      final cancel = todos.watch(events.add, onError: errors.add);
      await settle();

      alice.dataEvents.add(DataUpdated(AtKey.fromString('t1.$_ns@alice')));
      await settle();
      alice.dataEvents.add(DataDeleted(AtKey.fromString('t1.$_ns@alice')));
      await settle();
      await cancel();
      await settle();
      alice.dataEvents.add(DataUpdated(AtKey.fromString('t1.$_ns@alice')));
      await settle();

      expect(events, [
        {'type': 'updated', 'id': 't1', 'owner': '@alice'},
        {'type': 'deleted', 'id': 't1', 'owner': '@alice', 'wasExpired': false},
      ]);
      expect(errors, isEmpty);
    });

    test('An event for an unreadable item is delivered with its id and owner',
        () async {
      await bobSharesUnreadable('b1');
      final todos = await open();
      final events = <JsEvent>[];
      final errors = <JsCollectionsError>[];

      final cancel = todos.watch(events.add, onError: errors.add);
      await settle();
      alice.dataEvents.add(DataUpdated(AtKey.fromString('b1.$_ns@bob')));
      await settle();
      await cancel();

      expect(events, [
        {'type': 'updated', 'id': 'b1', 'owner': '@bob'}
      ]);
      expect(errors, isEmpty);
      await expectLater(
        todos.get(bobs('b1')),
        _rejectsWith(W8.unreadable, id: 'b1', owner: '@bob'),
      );
    });

    test('Events for other type tags and missing items are delivered',
        () async {
      final todos = await open();
      await rawCollection(alice, _ns, writeTypeTag: 'Other')
          .create(obj: {'title': 'other'}, id: 'o1');
      final events = <JsEvent>[];
      final errors = <JsCollectionsError>[];

      final cancel = todos.watch(events.add, onError: errors.add);
      await settle();
      alice.dataEvents.add(DataUpdated(AtKey.fromString('o1.$_ns@alice')));
      await settle();
      alice.dataEvents.add(
          DataDeleted(AtKey.fromString('o1.$_ns@alice'), wasExpired: true));
      await settle();
      alice.dataEvents.add(DataUpdated(AtKey.fromString('gone.$_ns@alice')));
      await settle();
      await cancel();

      expect(events, [
        {'type': 'updated', 'id': 'o1', 'owner': '@alice'},
        {'type': 'deleted', 'id': 'o1', 'owner': '@alice', 'wasExpired': true},
        {'type': 'updated', 'id': 'gone', 'owner': '@alice'},
      ]);
      expect(errors, isEmpty);
    });

    group('with test-controlled events', () {
      late StreamController<CEvent> upstream;
      late JsCollectionsAdapter todos;

      setUp(() {
        upstream = StreamController<CEvent>.broadcast();
        final collection = MockAtCollection();
        when(collection.watch).thenAnswer((_) => upstream.stream);
        todos = JsCollectionsAdapter(collection);
      });

      tearDown(() => upstream.close());

      test(
          'Every CEvent subtype maps to its JS event and an unknown one to unknown',
          () async {
        final alice = '@alice'.toAtsign();
        final bob = '@bob'.toAtsign();
        final at = DateTime.utc(2030, 1, 2);
        final ancestry = [CAncestor(id: 'p1', subName: 'notes', owner: bob)];
        final events = <JsEvent>[];
        final errors = <JsCollectionsError>[];

        final cancel = todos.watch(events.add, onError: errors.add);
        for (final event in <CEvent>[
          CItemUpdated(owner: alice, id: 'i1'),
          CItemDeleted(owner: alice, id: 'i1', wasExpired: true),
          CItemAvailable(owner: alice, id: 'i1', availableAt: at),
          CItemExpiringSoon(
              owner: alice,
              id: 'i1',
              expiresAt: at,
              leadTime: const Duration(minutes: 5)),
          CReadReceipt(owner: alice, id: 'i1', from: bob, readAt: at),
          CSubItemUpdated(owner: bob, id: 'n1', ancestry: ancestry),
          CSubItemDeleted(owner: bob, id: 'n1', ancestry: ancestry),
          _LaterEvent(),
        ]) {
          upstream.add(event);
        }
        await settle();
        await cancel();

        final ms = at.millisecondsSinceEpoch;
        final chain = [
          {'id': 'p1', 'subName': 'notes', 'owner': '@bob'}
        ];
        expect(events, [
          {'type': 'updated', 'id': 'i1', 'owner': '@alice'},
          {
            'type': 'deleted',
            'id': 'i1',
            'owner': '@alice',
            'wasExpired': true
          },
          {
            'type': 'available',
            'id': 'i1',
            'owner': '@alice',
            'availableAt': ms
          },
          {
            'type': 'expiringSoon',
            'id': 'i1',
            'owner': '@alice',
            'expiresAt': ms,
            'leadTimeMs': 300000
          },
          {
            'type': 'readReceipt',
            'id': 'i1',
            'owner': '@alice',
            'from': '@bob',
            'readAt': ms
          },
          {
            'type': 'subItemUpdated',
            'id': 'n1',
            'owner': '@bob',
            'ancestry': chain
          },
          {
            'type': 'subItemDeleted',
            'id': 'n1',
            'owner': '@bob',
            'ancestry': chain
          },
          {'type': 'unknown', 'id': 'later', 'owner': '@alice'},
        ]);
        expect(errors, isEmpty);
      });

      test(
          'A stream error reaches onError as a W8 error and later events still arrive',
          () async {
        final events = <JsEvent>[];
        final errors = <JsCollectionsError>[];

        final cancel = todos.watch(events.add, onError: errors.add);
        upstream.addError(CItemReadException(
            AtKey.fromString('b1.$_ns@bob'), const FormatException('bad')));
        upstream.add(CItemUpdated(owner: '@alice'.toAtsign(), id: 'i1'));
        await settle();
        await cancel();

        expect(errors.single.code, W8.unreadable);
        expect(errors.single.id, 'b1');
        expect(errors.single.owner, '@bob');
        expect(events, [
          {'type': 'updated', 'id': 'i1', 'owner': '@alice'}
        ]);
      });
    });
  });

  // ---------------------------------------------------------------------------
  group('structure', () {
    test('The adapter is not exported and reaches no web-only API', () async {
      final adapter = await Isolate.resolvePackageUri(Uri.parse(
          'package:at_client_wasm/src/collections/js_collections_adapter.dart'));
      expect(adapter, isNotNull);
      final libDir = adapter!.resolve('../../');

      final topLevel = Directory.fromUri(libDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(topLevel, isNotEmpty);
      for (final library in topLevel) {
        expect(library.readAsStringSync(), isNot(contains('collections/')),
            reason: library.path);
      }

      final visited = <String>{};
      final pending = [adapter.toFilePath()];
      final importPattern =
          RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true);
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
      expect(visited, contains(adapter.toFilePath()));
    });
  });
}
