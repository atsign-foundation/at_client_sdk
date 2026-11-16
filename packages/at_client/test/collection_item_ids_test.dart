import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Catalogue: features/at_client/collection_item_ids.feature
void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  const namespace = 'todos.demo';
  final alice = '@alice'.toAtsign();
  final bob = '@bob'.toAtsign();
  final long = 'a' * 65;

  late MockAtClient atClient;
  late StreamController<AtNotification> notifications;

  /// @alice's local keystore: each key's string form, its key and its value.
  late Map<String, ({AtKey key, String value})> store;

  String envelope(String obj) => jsonEncode({'type': 'n/a', 'obj': obj});

  /// Writes a record directly, as another client writes it.
  void seed(String key, String obj) {
    final atKey = AtKey.fromString(key)
      ..metadata = (Metadata()
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().toUtc().add(const Duration(days: 7)));
    store[atKey.toString()] = (key: atKey, value: envelope(obj));
  }

  setUp(() {
    atClient = MockAtClient();
    notifications = StreamController<AtNotification>.broadcast();
    store = {};
    when(() => atClient.atSign).thenReturn(alice);
    when(() => atClient.getAtKeys(regex: any(named: 'regex')))
        .thenAnswer((inv) async {
      final re = RegExp(inv.namedArguments[#regex] as String);
      return [
        for (final e in store.entries)
          if (!e.key.startsWith('_') && re.hasMatch(e.key)) e.value.key
      ];
    });
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final k = inv.positionalArguments.first as AtKey;
      final stored = store[k.toString()];
      if (stored == null) throw KeyNotFoundException('no value for $k');
      return AtValue()
        ..value = stored.value
        ..metadata = stored.key.metadata;
    });
    when(() => atClient.put(any(), any())).thenAnswer((inv) async {
      final k = inv.positionalArguments[0] as AtKey;
      final metadata = k.metadata
        ..createdAt ??= DateTime.now().toUtc()
        ..expiresAt ??= DateTime.now().toUtc().add(const Duration(days: 7));
      store[k.toString()] = (
        key: AtKey.fromString(k.toString())..metadata = metadata,
        value: inv.positionalArguments[1] as String
      );
      return true;
    });
    when(() => atClient.delete(any())).thenAnswer((inv) async {
      store.remove((inv.positionalArguments.first as AtKey).toString());
      return true;
    });
  });

  tearDown(() async {
    await notifications.close();
  });

  /// A collection "todos.demo" of @alice, with no read or write recorded.
  Future<AtCollection<String>> todos() async {
    final c = collectionWithInjectedNotifications<String>(
      atClient,
      namespace,
      const Duration(days: 7),
      notifications: notifications.stream,
    );
    await pumpEventQueue();
    clearInteractions(atClient);
    return c;
  }

  void expectNothingWritten() {
    verifyNever(() => atClient.put(any(), any()));
    verifyNever(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions')));
    verifyNever(() => atClient.delete(any()));
    verifyNever(() => atClient.delete(any(),
        deleteRequestOptions: any(named: 'deleteRequestOptions')));
  }

  void expectNothingRead() {
    verifyNever(() => atClient.get(any()));
    verifyNever(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions')));
    verifyNever(() => atClient.getAtKeys(regex: any(named: 'regex')));
  }

  void expectNothingReadOrWritten() {
    expectNothingRead();
    expectNothingWritten();
  }

  Matcher refusedId(String id, String rule) => throwsA(isA<ArgumentError>()
      .having((e) => e.name, 'name', 'id')
      .having((e) => e.invalidValue, 'invalidValue', id)
      .having((e) => '${e.message}', 'message', contains(rule)));

  const structureRule = 'whitespace or a control character';
  const underscoreRule = 'must not start with "_"';
  const newIdRule = 'a new item id must be 1 to 64 characters';

  Matcher refusesStructure(String id) => refusedId(id, structureRule);
  Matcher refusesNewId(String id) => refusedId(id, newIdRule);

  // Every call that takes an id

  test(
      'Given an id containing ":", when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: 'a:b'), refusesStructure('a:b'));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id containing "@", when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: 'a@b'), refusesStructure('a@b'));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id containing a space, when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: 'a b'), refusesStructure('a b'));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id containing a newline, when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: 'a\nb'), refusesStructure('a\nb'));
    expectNothingReadOrWritten();
  });

  test(
      "Given an id containing a newline, when create is called, then the ArgumentError's text is a single line",
      () async {
    final c = await todos();
    await expectLater(
      c.create(obj: 'v', id: 'a\nb'),
      throwsA(isA<ArgumentError>()
          .having((e) => '$e', 'text', isNot(contains('\n')))
          .having((e) => '$e', 'text', contains(r'"a\nb"'))),
    );
  });

  test(
      'Given an empty id, when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: ''), refusesStructure(''));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id starting with "_", when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(
        c.create(obj: 'v', id: '_a'), refusedId('_a', underscoreRule));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id containing ".", when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: 'a.b'), refusesStructure('a.b'));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id containing ":", when upsert is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.upsert(obj: 'v', id: 'a:b'), refusesStructure('a:b'));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id containing ":", when draft is called, then ArgumentError is thrown',
      () async {
    final c = await todos();
    expect(() => c.draft(obj: 'v', id: 'a:b'), refusesStructure('a:b'));
  });

  test(
      'Given an id containing "@", when draft is called, then ArgumentError is thrown',
      () async {
    final c = await todos();
    expect(() => c.draft(obj: 'v', id: 'a@b'), refusesStructure('a@b'));
  });

  test(
      'Given an id containing ":", when get is called, then ArgumentError is thrown and nothing is read',
      () async {
    final c = await todos();
    await expectLater(c.get('a:b', alice), refusesStructure('a:b'));
    expectNothingRead();
  });

  test(
      'Given an id containing ":", when getOrNull is called, then ArgumentError is thrown and nothing is read',
      () async {
    final c = await todos();
    await expectLater(c.getOrNull('a:b', alice), refusesStructure('a:b'));
    expectNothingRead();
  });

  test(
      'Given an id containing "@", when exists is called, then ArgumentError is thrown and nothing is read',
      () async {
    final c = await todos();
    await expectLater(c.exists('a@b', alice), refusesStructure('a@b'));
    expectNothingRead();
  });

  test(
      'Given an id containing ":", when getItems is called with that id, then ArgumentError is thrown and nothing is read',
      () async {
    final c = await todos();
    await expectLater(c.getItems(id: 'a:b'), refusesStructure('a:b'));
    expectNothingRead();
  });

  test(
      'Given an id containing ":", when getItemsAsStream is called with that id, then ArgumentError is thrown and nothing is read',
      () async {
    final c = await todos();
    expect(() => c.getItemsAsStream(id: 'a:b'), refusesStructure('a:b'));
    expectNothingRead();
  });

  test(
      'Given an item @bob shares under an id starting with "_", when get is called with that id and @bob, then it returns the item',
      () async {
    seed('cached:@alice:_a.$namespace@bob', 'from bob');
    final c = await todos();

    final item = await c.get('_a', bob);

    expect(item.id, '_a');
    expect(item.owner, bob);
    expect(item.obj, 'from bob');
  });

  // A new item's id

  test(
      'Given an id of 65 characters, when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: long), refusesNewId(long));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id of 64 characters of a-z, 0-9, "-" and "_", when create is called, then get returns the item by that id',
      () async {
    final id = 'a${'0-' * 31}_';
    expect(id.length, 64);
    final c = await todos();

    await c.create(obj: 'v', id: id);

    final item = await c.get(id, alice);
    expect(item.id, id);
    expect(item.obj, 'v');
  });

  test(
      'Given an id starting with "-", when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: '-a'), refusesNewId('-a'));
    expectNothingReadOrWritten();
  });

  test(
      'Given an id containing "*", when create is called, then ArgumentError is thrown and nothing is read or written',
      () async {
    final c = await todos();
    await expectLater(c.create(obj: 'v', id: 'a*b'), refusesNewId('a*b'));
    expectNothingReadOrWritten();
  });

  test(
      'Given no item with a 65-character id, when upsert is called with that id, then ArgumentError is thrown and nothing is written',
      () async {
    final c = await todos();
    await expectLater(c.upsert(obj: 'v', id: long), refusesNewId(long));
    verify(() => atClient.get(any())).called(1);
    expectNothingWritten();
    expect(store, isEmpty);
  });

  test(
      "Given no id, when create is called, then the item's id is 8 characters of a-z and 0-9",
      () async {
    final c = await todos();
    final item = await c.create(obj: 'v');
    expect(item.id, matches(RegExp(r'^[a-z0-9]{8}$')));
  });

  // Upper case

  test(
      'Given the id "Todo-1", when create is called, then the item returned has the id "todo-1"',
      () async {
    final c = await todos();

    final item = await c.create(obj: 'v', id: 'Todo-1');

    expect(item.id, 'todo-1');
    expect(store.keys, contains('todo-1.$namespace@alice'));
  });

  test(
      'Given an item created with the id "todo-1", when get is called with "TODO-1", then it returns that item',
      () async {
    final c = await todos();
    await c.create(obj: 'v', id: 'todo-1');

    final item = await c.get('TODO-1', alice);

    expect(item.id, 'todo-1');
    expect(item.obj, 'v');
  });

  // An item already stored under an id outside the new-item set

  test(
      'Given a stored item whose id is 65 characters, when getItems is called, then it lists the item under that id',
      () async {
    seed('$long.$namespace@alice', 'old');
    final c = await todos();

    final items = await c.getItems();

    expect([for (final i in items) i.id], [long]);
  });

  test(
      'Given a stored item whose id starts with "-", when get is called with that id, then it returns the item',
      () async {
    seed('-a.$namespace@alice', 'old');
    final c = await todos();

    final item = await c.get('-a', alice);

    expect(item.id, '-a');
    expect(item.obj, 'old');
  });

  test(
      'Given a stored item whose id is 65 characters, when a draft with that id and a new value is passed to update, then the item holds the new value',
      () async {
    seed('$long.$namespace@alice', 'old');
    final c = await todos();

    await c.update(c.draft(obj: 'new', id: long));

    expect((await c.get(long, alice)).obj, 'new');
  });

  test(
      'Given a stored item whose id contains "*", when upsert is called with that id, then the item holds the new value',
      () async {
    seed('a*b.$namespace@alice', 'old');
    final c = await todos();

    await c.upsert(obj: 'new', id: 'a*b');

    expect((await c.get('a*b', alice)).obj, 'new');
  });

  test(
      'Given a stored item whose id starts with "-", when updateSharedWith adds @bob, then a copy for @bob is written',
      () async {
    seed('-a.$namespace@alice', 'old');
    final c = await todos();
    final item = await c.get('-a', alice);

    await c.updateSharedWith(item, {bob});

    expect(store.keys, contains('@bob:-a.$namespace@alice'));
    expect(jsonDecode(store['@bob:-a.$namespace@alice']!.value)['obj'], 'old');
  });

  test(
      'Given a stored item whose id is 65 characters, when delete is called, then no key of the item remains',
      () async {
    seed('$long.$namespace@alice', 'old');
    seed('@bob:$long.$namespace@alice', 'old');
    final c = await todos();
    final item = await c.get(long, alice);

    await c.delete(item);

    expect(
        store.keys.where((k) => k.contains('$long.$namespace@alice')), isEmpty);
  });

  // Sub-collection names

  test(
      'Given a subName containing ":", when subCollection is called, then ArgumentError is thrown',
      () async {
    final c = await todos();
    final parent = await c.create(obj: 'v', id: 'p1');

    expect(
      () => c.subCollection<String>(
        parent: parent,
        subName: 'a:b',
        defaultExpiration: const Duration(days: 1),
      ),
      throwsA(isA<ArgumentError>()
          .having((e) => e.name, 'name', 'subName')
          .having((e) => '${e.message}', 'message', contains(structureRule))),
    );
  });
}
