// Scenarios: features/at_client_wasm/js_collections_adapter.feature. Each
// test is named after its scenario.

import 'dart:async';
import 'dart:convert';

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

/// An error type the adapter has no name for, standing in for one a later
/// at_client throws.
final class _LaterError {}

Matcher _rejectsWith(String code, {String? id, String? owner, String? kind}) =>
    throwsA(isA<JsCollectionsError>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.id, 'id', id ?? anything)
        .having((e) => e.owner, 'owner', owner ?? anything)
        .having((e) => e.kind, 'kind', kind ?? anything));

void main() {
  setUpAll(registerAdapterFallbacks);

  test('JsCollectionsError is an AtException and keeps its fields', () {
    final error = JsCollectionsError(
        CollectionErrorCodes.partialFailure, 'boom',
        id: 'i',
        owner: '@alice',
        kind: 'K',
        failures: const [
          {'op': 'put'}
        ]);
    expect(error, isA<AtException>());
    expect(error.code, CollectionErrorCodes.partialFailure);
    expect(error.message, 'boom');
    expect(error.id, 'i');
    expect(error.owner, '@alice');
    expect(error.kind, 'K');
    expect(error.failures, [
      {'op': 'put'}
    ]);
    expect(error.toString(),
        'JsCollectionsError(COLLECTION_PARTIAL_FAILURE): boom');
  });

  test('The error codes are the COLLECTION_ and COLLECTION_ITEM_ names', () {
    expect(
        {
          CollectionErrorCodes.invalidArgument: 'COLLECTION_INVALID_ARGUMENT',
          CollectionErrorCodes.partialFailure: 'COLLECTION_PARTIAL_FAILURE',
          CollectionErrorCodes.typeMismatch: 'COLLECTION_TYPE_MISMATCH',
          CollectionErrorCodes.failed: 'COLLECTION_FAILED',
          CollectionErrorCodes.notFound: 'COLLECTION_ITEM_NOT_FOUND',
          CollectionErrorCodes.notOwner: 'COLLECTION_ITEM_NOT_OWNER',
          CollectionErrorCodes.alreadyExists: 'COLLECTION_ITEM_ALREADY_EXISTS',
          CollectionErrorCodes.unreadable: 'COLLECTION_ITEM_UNREADABLE',
          CollectionErrorCodes.hasSubItems: 'COLLECTION_ITEM_HAS_SUB_ITEMS',
          CollectionErrorCodes.wrongType: 'COLLECTION_ITEM_WRONG_TYPE',
        }.entries.every((e) => e.key == e.value),
        isTrue);
  });

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

  Future<List<JsItem>> itemsOf(Future<JsListing> listing) async =>
      (await listing).items;

  Future<List<JsUnreadable>> unreadableOf(Future<JsListing> listing) async =>
      (await listing).unreadable;

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
  group('item ids', () {
    final long = 'a' * 65;

    test(
        'An item id AtCollection refuses rejects with COLLECTION_INVALID_ARGUMENT',
        () async {
      final todos = await open();

      for (final id in ['a:b', 'a@b', '', 'a.b', 'a b']) {
        for (final call in <String, Future<Object?> Function()>{
          'create': () => todos.create({'t': 1}, id: id),
          'get': () => todos.get(mine(id)),
          'update': () => todos.update(mine(id), {'t': 2}),
          'share': () => todos.share(mine(id), ['@bob']),
          'remove': () => todos.remove(mine(id)),
        }.entries) {
          await expectLater(
              call.value(),
              _rejectsWith(CollectionErrorCodes.invalidArgument,
                  kind: 'ArgumentError'),
              reason: '${call.key} of "$id"');
        }
      }
      verifyNever(() => alice.mock.put(any(), any()));
      expect(server.keyCount, 0);
    });

    test(
        'A create with an id starting with "_" rejects with COLLECTION_INVALID_ARGUMENT',
        () async {
      final todos = await open();

      await expectLater(
          todos.create({'t': 1}, id: '_a'),
          _rejectsWith(CollectionErrorCodes.invalidArgument,
              kind: 'ArgumentError'));

      verifyNever(() => alice.mock.put(any(), any()));
      expect(server.keyCount, 0);
    });

    test(
        'A create with an id of 65 characters rejects with COLLECTION_INVALID_ARGUMENT',
        () async {
      final todos = await open();

      await expectLater(
          todos.create({'t': 1}, id: long),
          _rejectsWith(CollectionErrorCodes.invalidArgument,
              kind: 'ArgumentError'));

      verifyNever(() => alice.mock.put(any(), any()));
      expect(server.keyCount, 0);
    });

    test('A create with the id "A1" returns the item with the id "a1"',
        () async {
      final todos = await open();

      final item = await todos.create({'t': 1}, id: 'A1');

      expect(item['id'], 'a1');
      expect(server.hasKey('a1.$_ns@alice'), isTrue);
    });

    test('A get with the id "A1" returns the item created as "a1"', () async {
      final todos = await open();
      await todos.create({'t': 1}, id: 'a1');

      final item = await todos.get(mine('A1'));

      expect(item?['id'], 'a1');
      expect(item?['data'], {'t': 1});
    });

    test(
        'A create with the id "A1" when "a1" exists rejects with COLLECTION_ITEM_ALREADY_EXISTS and the id "a1"',
        () async {
      final todos = await open();
      await todos.create({'t': 1}, id: 'a1');

      await expectLater(todos.create({'t': 2}, id: 'A1'),
          _rejectsWith(CollectionErrorCodes.alreadyExists, id: 'a1'));
    });

    test(
        'An update, share or remove of the missing id "B1" rejects with COLLECTION_ITEM_NOT_FOUND and the id "b1"',
        () async {
      final todos = await open();

      for (final call in <String, Future<Object?> Function()>{
        'update': () => todos.update(mine('B1'), {'t': 2}),
        'share': () => todos.share(mine('B1'), ['@bob']),
        'remove': () => todos.remove(mine('B1')),
      }.entries) {
        await expectLater(
            call.value(), _rejectsWith(CollectionErrorCodes.notFound, id: 'b1'),
            reason: call.key);
      }
    });

    test(
        'An update of the id "B1" owned by @bob rejects with COLLECTION_ITEM_NOT_OWNER and the id "b1"',
        () async {
      final todos = await open();

      await expectLater(todos.update(bobs('B1'), {'t': 2}),
          _rejectsWith(CollectionErrorCodes.notOwner, id: 'b1'));
    });

    test(
        'An update, share or remove of the missing id "b1" owned by "@ALICE" rejects with COLLECTION_ITEM_NOT_FOUND and the owner "@alice"',
        () async {
      final todos = await open();
      final address = (id: 'b1', owner: '@ALICE');

      for (final call in <String, Future<Object?> Function()>{
        'update': () => todos.update(address, {'t': 2}),
        'share': () => todos.share(address, ['@bob']),
        'remove': () => todos.remove(address),
      }.entries) {
        await expectLater(
            call.value(),
            _rejectsWith(CollectionErrorCodes.notFound,
                id: 'b1', owner: '@alice'),
            reason: call.key);
      }
    });

    test(
        'An update, share or remove of the id "b1" owned by "a b", which is not an atSign, rejects with COLLECTION_INVALID_ARGUMENT and the owner "a b"',
        () async {
      final todos = await open();
      final address = (id: 'b1', owner: 'a b');

      for (final call in <String, Future<Object?> Function()>{
        'update': () => todos.update(address, {'t': 2}),
        'share': () => todos.share(address, ['@bob']),
        'remove': () => todos.remove(address),
      }.entries) {
        late Future<Object?> pending;
        expect(() => pending = call.value(), returnsNormally,
            reason: '${call.key} returns a Future');
        await expectLater(
            pending,
            _rejectsWith(CollectionErrorCodes.invalidArgument,
                id: 'b1', owner: 'a b', kind: 'InvalidAtSignException'),
            reason: call.key);
      }
    });

    test('A get addresses an item already stored under a 65-character id',
        () async {
      server.putRaw(
          '$long.$_ns@alice',
          jsonEncode({
            'type': 'Todo',
            'obj': {'t': 1}
          }));
      final todos = await open();

      final item = await todos.get(mine(long));

      expect(item?['id'], long);
      expect(item?['owner'], '@alice');
      expect(item?['data'], {'t': 1});
    });

    test('An item id of 64 allowed characters round-trips', () async {
      final todos = await open();
      final id = 'a${'0-' * 31}_';
      expect(id.length, 64);

      await todos.create({'t': 1}, id: id);

      expect((await todos.get(mine(id)))?['id'], id);
    });
  });

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

    test('An unknown eventSource rejects with COLLECTION_INVALID_ARGUMENT',
        () async {
      await expectLater(
        JsCollectionsAdapter.open(alice.mock,
            namespace: _ns,
            type: 'Todo',
            expirationMs: _day.inMilliseconds,
            eventSource: 'bogus'),
        _rejectsWith(CollectionErrorCodes.invalidArgument),
      );
    });

    test('An empty type rejects with COLLECTION_INVALID_ARGUMENT', () async {
      await expectLater(
          open(type: ''), _rejectsWith(CollectionErrorCodes.invalidArgument));
    });

    test('A non-positive expirationMs rejects with COLLECTION_INVALID_ARGUMENT',
        () async {
      for (final ms in [0, -1]) {
        await expectLater(
          JsCollectionsAdapter.open(alice.mock,
              namespace: _ns, type: 'Todo', expirationMs: ms),
          _rejectsWith(CollectionErrorCodes.invalidArgument),
        );
      }
      verifyNever(() => alice.mock.collection<Map<String, dynamic>>(
            any(),
            any(),
            eventSource: any(named: 'eventSource'),
            fromJson: any(named: 'fromJson'),
            typeTag: any(named: 'typeTag'),
            writeTypeTag: any(named: 'writeTypeTag'),
            cleanupOrphansOnCreation: any(named: 'cleanupOrphansOnCreation'),
          ));
    });

    test('A failed open rejects with COLLECTION_FAILED naming the error kind',
        () async {
      alice.failNextCollection(StateError('upstream down'));

      await expectLater(open(),
          _rejectsWith(CollectionErrorCodes.failed, kind: 'StateError'));
    });

    group('An error kind is a name the adapter knows or "Unknown"', () {
      test('An open fails with a known kind named by its literal', () async {
        alice.failNextCollection(AtKeyNotFoundException('gone'));
        await expectLater(
            open(),
            _rejectsWith(CollectionErrorCodes.notFound,
                kind: 'AtKeyNotFoundException'));

        alice.failNextCollection(FormatException('bad'));
        await expectLater(open(),
            _rejectsWith(CollectionErrorCodes.failed, kind: 'FormatException'));
      });

      test('A key-level write fails with a known kind named by its literal',
          () async {
        final todos = await open();
        alice.failPutsWith((key) => key.sharedWith?.toAtsign() == '@bob',
            TimeoutException('t'));

        await expectLater(
          todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']),
          throwsA(
              isA<JsCollectionsError>().having((e) => e.failures, 'failures', [
            {'op': 'put', 'recipient': '@bob', 'kind': 'TimeoutException'}
          ])),
        );
      });

      test('An error of a type the adapter does not know has kind "Unknown"',
          () async {
        alice.failNextCollection(_LaterError());

        await expectLater(
            open(), _rejectsWith(CollectionErrorCodes.failed, kind: 'Unknown'));
      });

      test('A failed key-level write of an unknown reason has kind "Unknown"',
          () async {
        final todos = await open();
        alice.failPutsWith(
            (key) => key.sharedWith?.toAtsign() == '@bob', _LaterError());

        await expectLater(
          todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']),
          throwsA(
              isA<JsCollectionsError>().having((e) => e.failures, 'failures', [
            {'op': 'put', 'recipient': '@bob', 'kind': 'Unknown'}
          ])),
        );
      });
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

    test(
        'A create with an existing id rejects with COLLECTION_ITEM_ALREADY_EXISTS',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1');

      await expectLater(
        todos.create({'title': 'b'}, id: 'i1'),
        _rejectsWith(CollectionErrorCodes.alreadyExists),
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
        'A get of an unreadable item rejects with COLLECTION_ITEM_UNREADABLE naming id and owner',
        () async {
      await bobSharesUnreadable('b1');
      final todos = await open();

      await expectLater(
        todos.get(bobs('b1')),
        throwsA(isA<JsCollectionsError>()
            .having((e) => e.code, 'code', CollectionErrorCodes.unreadable)
            .having((e) => e.id, 'id', 'b1')
            .having((e) => e.owner, 'owner', '@bob')
            .having((e) => e.message, 'message', isNot(contains('json')))
            .having((e) => e.message, 'message',
                isNot(contains('FormatException')))),
      );
    });

    test("An item's owner comes from the key's sharedBy, never from its data",
        () async {
      await bobShares('f1', {'owner': '@carol', 'sharedBy': '@carol'});
      server.overwriteValues(
        (key) =>
            key.sharedBy?.toAtsign() == '@bob'.toAtsign() &&
            key.sharedWith?.toAtsign() == '@alice'.toAtsign(),
        jsonEncode({
          'type': 'Todo',
          'owner': '@carol',
          'sharedBy': '@carol',
          'obj': {'owner': '@carol', 'sharedBy': '@carol'},
        }),
      );
      final todos = await open();

      final got = await todos.get(bobs('f1'));
      final listed = (await todos.list()).items;

      expect(got?['owner'], '@bob');
      expect(ids(listed), ['f1']);
      expect(listed.single['owner'], '@bob');
      expect(await todos.get(mine('f1')), isNull);
      await expectLater(todos.update((id: 'f1', owner: '@carol'), {'x': 1}),
          _rejectsWith(CollectionErrorCodes.notOwner, owner: '@carol'));
    });

    test('A list returns readable items and reports unreadable ones', () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'a1');
      await bobSharesUnreadable('b1');

      expect(ids(await itemsOf(todos.list())), ['a1']);
      expect(await unreadableOf(todos.list()),
          [(id: 'b1', owner: '@bob', code: CollectionErrorCodes.unreadable)]);
      await expectLater(
        todos.get(bobs('b1')),
        _rejectsWith(CollectionErrorCodes.unreadable, id: 'b1', owner: '@bob'),
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

      final listed = await itemsOf(todos.list());
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
        for (final item in await itemsOf(todos.list())) item['id']: item['type']
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

    test(
        "An update of another type's item rejects with COLLECTION_ITEM_WRONG_TYPE",
        () async {
      final todos = await open();
      await rawCollection(alice, _ns, writeTypeTag: 'Other')
          .create(obj: {'title': 'other'}, id: 'o1');

      await expectLater(
          todos.update(mine('o1'), {'title': 'changed'}),
          _rejectsWith(CollectionErrorCodes.wrongType,
              id: 'o1', owner: '@alice'));

      final stored = (await todos.get(mine('o1')))!;
      expect(stored['type'], 'Other');
      expect(stored['data'], {'title': 'other'});
    });

    test('An update adopts an untagged item and returns its stored createdAt',
        () async {
      final todos = await open();
      await rawCollection(alice, _ns)
          .create(obj: {'title': 'untagged'}, id: 'n1');
      final before = (await todos.get(mine('n1')))!;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final updated = await todos.update(mine('n1'), {'title': 'adopted'});

      expect(updated['type'], 'Todo');
      expect(updated['createdAt'], before['createdAt']);
      expect((await todos.get(mine('n1')))?['type'], 'Todo');
    });

    test('An update of a missing item rejects with COLLECTION_ITEM_NOT_FOUND',
        () async {
      final todos = await open();

      await expectLater(
        todos.update(mine('nope'), {'title': 'x'}),
        _rejectsWith(CollectionErrorCodes.notFound,
            id: 'nope', owner: '@alice'),
      );
    });

    test(
        "An update, share or remove of another owner's item rejects with COLLECTION_ITEM_NOT_OWNER",
        () async {
      await bobShares('b1', {'title': 'bob'});
      final todos = await open();

      await expectLater(todos.update(bobs('b1'), {'title': 'mine'}),
          _rejectsWith(CollectionErrorCodes.notOwner, id: 'b1', owner: '@bob'));
      await expectLater(todos.share(bobs('b1'), ['@carol']),
          _rejectsWith(CollectionErrorCodes.notOwner, id: 'b1', owner: '@bob'));
      await expectLater(todos.remove(bobs('b1')),
          _rejectsWith(CollectionErrorCodes.notOwner, id: 'b1', owner: '@bob'));

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

    test('A share of a missing item rejects with COLLECTION_ITEM_NOT_FOUND',
        () async {
      final todos = await open();

      await expectLater(
        todos.share(mine('nope'), ['@bob']),
        _rejectsWith(CollectionErrorCodes.notFound,
            id: 'nope', owner: '@alice'),
      );
    });

    test(
        'A share with an invalid atSign rejects with COLLECTION_INVALID_ARGUMENT',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']);

      await expectLater(
        todos.share(mine('i1'), ['@a@b']),
        _rejectsWith(CollectionErrorCodes.invalidArgument),
      );
      expect((await todos.get(mine('i1')))?['sharedWith'], ['@bob']);
    });

    test(
        'A partial write failure rejects with COLLECTION_PARTIAL_FAILURE naming the recipient',
        () async {
      final todos = await open();
      alice.failPutsFor((key) => key.sharedWith?.toAtsign() == '@bob');

      await expectLater(
        todos.create({'title': 'a'}, id: 'i1', sharedWith: ['@bob']),
        throwsA(isA<JsCollectionsError>()
            .having((e) => e.code, 'code', CollectionErrorCodes.partialFailure)
            .having((e) => e.failures, 'failures', [
          {'op': 'put', 'recipient': '@bob', 'kind': 'AtClientException'}
        ])),
      );
    });

    test(
        'A partial failure on a create without an id rejects with the written id and owner',
        () async {
      final todos = await open();
      alice.failPutsFor((key) => key.sharedWith?.toAtsign() == '@bob');

      final error = await todos
          .create({'title': 'a'}, sharedWith: ['@bob'])
          .then<JsCollectionsError?>((_) => null)
          .catchError((Object e) => e as JsCollectionsError);

      expect(error, isNotNull);
      expect(error!.code, CollectionErrorCodes.partialFailure);
      expect(error.id, isNotNull);
      expect(error.owner, '@alice');
      expect(await todos.get(mine(error.id!)), isNotNull);
    });

    test(
        'A remove deletes the item and a missing item rejects with COLLECTION_ITEM_NOT_FOUND',
        () async {
      final todos = await open();
      await todos.create({'title': 'a'}, id: 'i1');

      await todos.remove(mine('i1'));

      expect(await todos.get(mine('i1')), isNull);
      await expectLater(
        todos.remove(mine('i1')),
        _rejectsWith(CollectionErrorCodes.notFound, id: 'i1', owner: '@alice'),
      );
    });

    test(
        'A remove of an item with sub-items rejects with COLLECTION_ITEM_HAS_SUB_ITEMS unless cascade',
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
        _rejectsWith(CollectionErrorCodes.hasSubItems,
            id: 'p1', owner: '@alice'),
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
        ids(await itemsOf(todos.query([(path: path, op: op, value: value)])))
            .toSet();

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

      final both = await itemsOf(todos.query([
        (path: 'done', op: '==', value: false),
        (path: 'prio', op: '>', value: 0),
      ]));

      expect(ids(both), ['a']);
    });

    test(
        'An ordering where over mixed types rejects with COLLECTION_TYPE_MISMATCH',
        () async {
      final todos = await open();
      await todos.create({'prio': 1}, id: 'n1');
      await todos.create({'prio': 'high'}, id: 'h');
      await todos.create({'prio': true}, id: 't');

      await expectLater(
        todos.query([(path: 'prio', op: '<', value: 5)]),
        _rejectsWith(CollectionErrorCodes.typeMismatch),
      );
    });

    test(
        'An unknown or reserved operator or a bad path or value rejects with COLLECTION_INVALID_ARGUMENT',
        () async {
      final todos = await seeded();
      Matcher naming(String text) => throwsA(isA<JsCollectionsError>()
          .having((e) => e.code, 'code', CollectionErrorCodes.invalidArgument)
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

    test('A query returns matching readable items and reports unreadable ones',
        () async {
      final todos = await seeded();
      await bobSharesUnreadable('b1');

      final clause = [(path: 'done', op: '==', value: false)];

      expect(ids(await itemsOf(todos.query(clause))).toSet(), {'a', 'c'});
      expect(await unreadableOf(todos.query(clause)),
          [(id: 'b1', owner: '@bob', code: CollectionErrorCodes.unreadable)]);
    });

    test(
        'A query with where clauses over a set with an unreadable record keeps upstream order',
        () async {
      final todos = await open();
      const prios = {'c': 3, 'a': 1, 'a-b': 2, 'd': 4};
      for (final entry in prios.entries) {
        await todos.create({'prio': entry.value}, id: entry.key);
      }
      final upstream = [
        for (final item in await rawCollection(alice, _ns).getItems())
          if ((item.obj['prio'] as int) >= 2 && item.obj['prio'] != 4) item.id
      ];
      expect(upstream.length, 2);
      await bobSharesUnreadable('a-bb');
      await bobSharesUnreadable('zz');

      final clauses = [
        (path: 'prio', op: '>=', value: 2),
        (path: 'prio', op: '<', value: 4),
      ];

      expect(ids(await itemsOf(todos.query(clauses))), upstream);
      expect(
        [for (final u in await unreadableOf(todos.query(clauses))) u.id],
        unorderedEquals(['a-bb', 'zz']),
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
        _rejectsWith(CollectionErrorCodes.unreadable, id: 'b1', owner: '@bob'),
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
          'A stream error reaches onError as a collection error and later events still arrive',
          () async {
        final events = <JsEvent>[];
        final errors = <JsCollectionsError>[];

        final cancel = todos.watch(events.add, onError: errors.add);
        upstream.addError(CItemReadException(
            AtKey.fromString('b1.$_ns@bob'), const FormatException('bad')));
        upstream.add(CItemUpdated(owner: '@alice'.toAtsign(), id: 'i1'));
        await settle();
        await cancel();

        expect(errors.single.code, CollectionErrorCodes.unreadable);
        expect(errors.single.id, 'b1');
        expect(errors.single.owner, '@bob');
        expect(events, [
          {'type': 'updated', 'id': 'i1', 'owner': '@alice'}
        ]);
      });
    });
  });
}
