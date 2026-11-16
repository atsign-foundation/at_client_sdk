import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/storage/memory/memory_at_key_value_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';

/// Catalogue: features/at_client/collection_item_ids.feature
void main() {
  final logs = RecordedLogs();

  setUpAll(() {
    logs.installOn();
    registerFallbackValue(FakeAtKey());
  });

  const namespace = 'todos.demo';
  final alice = '@alice'.toAtsign();
  final bob = '@bob'.toAtsign();
  final long = 'a' * 65;

  late MockAtClient atClient;
  late StreamController<AtNotification> notifications;

  /// @alice's local keystore: each key's string form, its key and its value.
  late Map<String, ({AtKey key, String value})> store;

  String envelope(String obj) => jsonEncode({'type': 'n/a', 'obj': obj});

  /// Writes a record directly, as another client writes it; a `cached:` key
  /// keeps its prefix, as a received copy does.
  void seed(String key, String obj) {
    final parsed = AtKey.fromString(key);
    final atKey = parsed
      ..metadata = (Metadata()
        ..isCached = parsed.metadata.isCached
        ..createdAt = DateTime.now().toUtc()
        ..expiresAt = DateTime.now().toUtc().add(const Duration(days: 7)));
    store[atKey.toString()] = (key: atKey, value: envelope(obj));
  }

  setUp(() {
    logs.records.clear();
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

  /// Gives @alice a local keystore, as the notification mirror writes to it.
  MemoryAtKeyValueStore stubLocalKeyStore() {
    final keyStore = MemoryAtKeyValueStore('@alice');
    final local = MockLocalSecondary();
    when(() => local.keyStore).thenReturn(keyStore);
    when(() => atClient.getLocalSecondary()).thenReturn(local);
    return keyStore;
  }

  Future<List<String>> keysIn(MemoryAtKeyValueStore keyStore) async =>
      (await keyStore.getKeys()).toList();

  /// [notification] carrying metadata, as a notification from an atServer
  /// does.
  AtNotification withMetadata(AtNotification notification) =>
      notification..metadata = (Metadata()..ttl = 60000);

  /// Stubs @alice's notification service, which a sub-collection subscribes
  /// to; returns how many subscriptions have been opened on it.
  int Function() stubNotificationService() {
    var opened = 0;
    final service = MockNotificationService();
    when(() => service.subscribe(
        regex: any(named: 'regex'),
        shouldDecrypt: any(named: 'shouldDecrypt'))).thenAnswer((_) {
      opened++;
      return const Stream.empty();
    });
    when(() => atClient.notificationService).thenReturn(service);
    return () => opened;
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

  var sequence = 0;

  /// A notification from @bob to @alice for [key].
  AtNotification fromBob(String key,
          {String operation = 'update', String? value}) =>
      AtNotification('n-${sequence++}', key, '@bob', '@alice',
          DateTime.now().millisecondsSinceEpoch, 'key', false,
          value: value, operation: operation);

  /// Each event [c] emits, as its kind, id and owner.
  List<String> eventsOf(AtCollection<String> c) {
    final events = <String>[];
    c.watch().listen((e) => events.add(switch (e) {
          CItemUpdated() => 'updated ${jsonEncode(e.id)} ${e.owner}',
          CItemDeleted() => 'deleted ${jsonEncode(e.id)} ${e.owner}',
          _ => '${e.runtimeType} ${jsonEncode(e.id)} ${e.owner}',
        }));
    return events;
  }

  /// A notification whose ids pass, sent after the one under test so that
  /// an empty result cannot come from nothing having been handled.
  const control = '@alice:ok.$namespace@bob';
  const controlUpdated = 'updated "ok" @bob';

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
      "Given an id containing U+2028, when create is called, then the ArgumentError's text holds no line or paragraph separator",
      () async {
    final c = await todos();
    await expectLater(
      c.create(obj: 'v', id: 'a\u2028b'),
      throwsA(isA<ArgumentError>()
          .having(
              (e) => '$e'
                  .runes
                  .where((r) => r == 0x2028 || r == 0x2029 || r == 0x85),
              'line or paragraph separators',
              isEmpty)
          .having((e) => e.invalidValue, 'invalidValue', 'a\u2028b')),
    );
  });

  test(
      'Given an id containing U+202E, when create is called, then the ArgumentError\'s text shows it escaped',
      () async {
    final c = await todos();
    final id = 'a${String.fromCharCode(0x202e)}b';
    final escaped = 'a' r'\' 'u' '202e' 'b';
    expect(escaped.length, 8, reason: 'the escape is six characters');
    await expectLater(
      c.create(obj: 'v', id: id),
      throwsA(isA<ArgumentError>()
          .having((e) => '$e', 'text', contains(escaped))
          .having((e) => '$e'.runes.contains(0x202e), 'holds U+202E', isFalse)
          .having((e) => e.invalidValue, 'invalidValue', id)),
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
      'Given an id starting with "_", when draft is called, then ArgumentError is thrown',
      () async {
    final c = await todos();
    expect(() => c.draft(obj: 'v', id: '_a'), refusedId('_a', underscoreRule));
  });

  test(
      'Given a stored item whose id starts with "_", when upsert is called with that id, then ArgumentError is thrown and nothing is read or written',
      () async {
    seed('_a.$namespace@alice', 'old');
    final c = await todos();
    await expectLater(
        c.upsert(obj: 'new', id: '_a'), refusedId('_a', underscoreRule));
    expectNothingReadOrWritten();
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

  test(
      'Given an item @bob shares under an id starting with "_", when exists is called with that id and @bob, then it returns true',
      () async {
    seed('cached:@alice:_a.$namespace@bob', 'from bob');
    final c = await todos();

    expect(await c.exists('_a', bob), isTrue);
  });

  test(
      'Given an id containing U+0000, when get is called, then ArgumentError is thrown and nothing is read',
      () async {
    final c = await todos();
    await expectLater(c.get('a\u0000b', alice), refusesStructure('a\u0000b'));
    expectNothingRead();
  });

  test(
      'Given an id containing U+009B, when get is called, then ArgumentError is thrown and nothing is read',
      () async {
    final c = await todos();
    await expectLater(c.get('a\u009bb', alice), refusesStructure('a\u009bb'));
    expectNothingRead();
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

  test(
      'Given an item @bob shares under an id containing a tab, when getItems is called, then it is not listed and a warning shows the id and @bob',
      () async {
    seed('cached:@alice:x\ty.$namespace@bob', 'from bob');
    seed('cached:@alice:ok.$namespace@bob', 'from bob');
    final c = await todos();

    final items = await c.getItems();

    expect([for (final i in items) i.id], ['ok'],
        reason: 'the item under the accepted id is listed, the other is not');
    final warnings = logs.at('WARNING').where((m) => m.contains(r'"x\ty"'));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('@bob'));
    expect(warnings.single, isNot(contains('\t')));
  });

  test(
      'Given a stored item with a 65-character id that this collection has found and that then expires, when upsert is called with that id, then ArgumentError is thrown and nothing is written',
      () async {
    seed('$long.$namespace@alice', 'old');
    final c = await todos();
    expect(await c.exists(long, alice), isTrue);
    store.remove('$long.$namespace@alice');
    // NOTE: the client's local read reports an expired key this way.
    when(() => atClient.get(any())).thenAnswer((inv) async =>
        throw AtKeyNotFoundException('${inv.positionalArguments.first} '
            'does not exist in keystore'));
    clearInteractions(atClient);

    await expectLater(c.upsert(obj: 'new', id: long), refusesNewId(long));
    expectNothingWritten();
  });

  test(
      'Given a stored item with a 65-character id that cannot be read, when upsert is called with that id, then the item holds the new value',
      () async {
    seed('$long.$namespace@alice', 'old');
    final c = await todos();
    final unreadable = AtKey.fromString('$long.$namespace@alice').toString();
    when(() => atClient.get(any())).thenAnswer((inv) async {
      final k = inv.positionalArguments.first as AtKey;
      if (k.toString() == unreadable) {
        throw AtDecryptionException('cannot decrypt $k');
      }
      final stored = store[k.toString()];
      if (stored == null) throw KeyNotFoundException('no value for $k');
      return AtValue()
        ..value = stored.value
        ..metadata = stored.key.metadata;
    });

    await c.upsert(obj: 'new', id: long);

    expect(jsonDecode(store[unreadable]!.value)['obj'], 'new');
  });

  // Sub-collection names

  test(
      'Given a subName containing ":", when subCollection is called, then ArgumentError is thrown',
      () async {
    final notificationService = MockNotificationService();
    when(() => notificationService.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt')))
        .thenAnswer((_) => const Stream.empty());
    when(() => atClient.notificationService).thenReturn(notificationService);
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

  test(
      'Given a subName "Comments", when an item is created in that sub-collection, then getItems on it lists the item',
      () async {
    stubNotificationService();
    final c = await todos();
    final parent = await c.create(obj: 'p', id: 'p1');
    final comments = c.subCollection<String>(
        parent: parent,
        subName: 'Comments',
        defaultExpiration: const Duration(days: 1));

    await comments.create(obj: 'v', id: 'c1');

    expect([for (final item in await comments.getItems()) item.id], ['c1']);
  });

  test(
      'Given an item in the sub-collection "comments" of "p1", when subCollection is called with the subName "COMMENTS", then getItems lists that item',
      () async {
    stubNotificationService();
    final c = await todos();
    final parent = await c.create(obj: 'p', id: 'p1');
    await c
        .subCollection<String>(
            parent: parent,
            subName: 'comments',
            defaultExpiration: const Duration(days: 1))
        .create(obj: 'v', id: 'c1');

    final shouted = c.subCollection<String>(
        parent: parent,
        subName: 'COMMENTS',
        defaultExpiration: const Duration(days: 1));

    expect([for (final item in await shouted.getItems()) item.id], ['c1']);
  });

  test(
      'Given a subName containing "#", when subCollection is called, then ArgumentError is thrown',
      () async {
    stubNotificationService();
    final c = await todos();
    final parent = await c.create(obj: 'v', id: 'p1');

    expect(
      () => c.subCollection<String>(
        parent: parent,
        subName: 'x#y',
        defaultExpiration: const Duration(days: 1),
      ),
      throwsA(isA<ArgumentError>()
          .having((e) => e.name, 'name', 'subName')
          .having((e) => e.invalidValue, 'invalidValue', 'x#y')),
    );
  });

  test(
      'Given a notification from @bob whose key\'s subName contains "|", when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:c1.a|b.p1.$namespace@bob'))
      ..add(fromBob(control));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
  });

  test(
      'Given items in the sub-collections "a", "aa" and "a*" of "p1", when getItems is called on the sub-collection "a*", then it lists only that sub-collection\'s item',
      () async {
    stubNotificationService();
    final c = await todos();
    final parent = await c.create(obj: 'p', id: 'p1');
    AtCollection<String> sub(String subName) => c.subCollection<String>(
        parent: parent,
        subName: subName,
        defaultExpiration: const Duration(days: 1));
    await sub('a').create(obj: 'in a', id: 'c1');
    await sub('aa').create(obj: 'in aa', id: 'c2');
    await sub('a*').create(obj: 'in a*', id: 'c3');

    expect([for (final item in await sub('a*').getItems()) item.id], ['c3']);
  });

  test(
      'Given an item with no parents in its envelope, two levels under the sub-collection "a*" of "p1", whose ancestors are stored, when cleanupOrphans is called, then the item is not deleted',
      () async {
    seed('p1.$namespace@alice', 'root');
    seed('b1.a*.p1.$namespace@alice', 'mid');
    seed('c1.x.b1.a*.p1.$namespace@alice', 'legacy leaf');
    seed('c2.x.b2.a*.p1.$namespace@alice', 'orphan leaf');
    final c = await todos();

    await c.cleanupOrphans();

    expect(store.keys, contains('c1.x.b1.a*.p1.$namespace@alice'),
        reason: 'its ancestors are stored');
    expect(store.keys, isNot(contains('c2.x.b2.a*.p1.$namespace@alice')),
        reason: 'control: the leaf whose parent b2 is absent is swept');
  });

  // Ids that arrive in events

  test(
      'Given a notification from @bob whose key\'s item id contains ":", when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:x:y.$namespace@bob'))
      ..add(fromBob(control));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
  });

  test(
      'Given a notification from @bob whose key\'s item id contains ":", when it reaches the collection, then a warning shows the id and @bob and not the value',
      () async {
    final c = await todos();
    eventsOf(c);

    notifications
        .add(fromBob('@alice:x:y.$namespace@bob', value: envelope('v-secret')));
    await pumpEventQueue();

    final warnings = logs.at('WARNING').where((m) => m.contains('"x:y"'));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('@bob'));
    expect(warnings.single, isNot(contains('v-secret')));
  });

  test(
      'Given a notification from @bob whose key\'s item id contains a newline, when it reaches the collection, then the warning is a single line',
      () async {
    final c = await todos();
    eventsOf(c);

    notifications.add(fromBob('@alice:x\ny.$namespace@bob'));
    await pumpEventQueue();

    final warnings =
        logs.at('WARNING').where((m) => m.contains(r'"x\ny"')).toList();
    expect(warnings, hasLength(1),
        reason: 'one warning shows the id with the newline escaped');
    expect(warnings.single, isNot(contains('\n')));
  });

  test(
      'Given a query watch and a notification from @bob whose key\'s item id contains a space, when it reaches the collection, then the watch emits no error',
      () async {
    final c = await todos();
    final errors = <Object>[];
    final snapshots = <int>[];
    final watching = c
        .query()
        .watch()
        .listen((l) => snapshots.add(l.length), onError: errors.add);
    addTearDown(watching.cancel);
    await pumpEventQueue();

    notifications.add(fromBob('@alice:x y.$namespace@bob'));
    await pumpEventQueue();
    seed('cached:@alice:ok.$namespace@bob', 'from bob');
    notifications.add(fromBob(control));
    await pumpEventQueue();

    expect(errors, isEmpty);
    expect(snapshots.last, 1,
        reason: 'the watch went on to show the control item');
  });

  test(
      'Given a delete notification from @bob whose key\'s item id contains ":", when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:x:y.$namespace@bob', operation: 'delete'))
      ..add(fromBob(control, operation: 'delete'));
    await pumpEventQueue();

    expect(events, ['deleted "ok" @bob']);
  });

  test(
      'Given a notification from @bob whose key\'s ancestor id contains ":", when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:c1.comments.x:y.$namespace@bob'))
      ..add(fromBob(control));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
  });

  test(
      'Given a notification from @bob whose key\'s subName contains ":", when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:c1.a:b.p1.$namespace@bob'))
      ..add(fromBob(control));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
  });

  test(
      'Given a notification from @bob with metadata whose key\'s item id is empty, when it reaches the collection, then nothing is written to the local keystore',
      () async {
    final keyStore = stubLocalKeyStore();
    final c = await todos();
    eventsOf(c);

    notifications.add(withMetadata(
        fromBob('@alice:.$namespace@bob', value: envelope('from bob'))));
    await pumpEventQueue();

    expect(await keysIn(keyStore), isEmpty);
    final warnings = logs.at('WARNING').where((m) => m.contains('item id ""'));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('@bob'));

    notifications
        .add(withMetadata(fromBob(control, value: envelope('from bob'))));
    await pumpEventQueue();
    expect(await keysIn(keyStore), ['cached:$control'],
        reason: 'the control notification is mirrored');
  });

  test(
      'Given a notification from @bob with metadata whose key\'s item id contains ":", when it reaches the collection, then a warning shows the id and @bob and nothing is written to the local keystore',
      () async {
    final keyStore = stubLocalKeyStore();
    final c = await todos();
    eventsOf(c);

    notifications.add(withMetadata(
        fromBob('@alice:x:y.$namespace@bob', value: envelope('from bob'))));
    await pumpEventQueue();

    final warnings = logs.at('WARNING').where((m) => m.contains('"x:y"'));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('@bob'));
    expect(await keysIn(keyStore), isEmpty);

    notifications
        .add(withMetadata(fromBob(control, value: envelope('from bob'))));
    await pumpEventQueue();
    expect(await keysIn(keyStore), ['cached:$control'],
        reason: 'the control notification is mirrored');
  });

  test(
      'Given a data event for a key @bob shares whose item id contains a tab, when it reaches the collection, then no event is emitted',
      () async {
    final dataEvents = StreamController<DataEvent>.broadcast();
    addTearDown(dataEvents.close);
    final c = collectionWithInjectedDataEvents<String>(
        atClient, namespace, const Duration(days: 7),
        dataEvents: dataEvents.stream);
    await pumpEventQueue();
    final events = eventsOf(c);

    dataEvents
      ..add(DataUpdated(AtKey.fromString('cached:@alice:x\ty.$namespace@bob')))
      ..add(DataUpdated(AtKey.fromString('cached:$control')));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
  });

  test(
      'Given a notification from @bob whose key\'s item id starts with "_", when it reaches the collection, then an update event with that id is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications.add(fromBob('@alice:_x.$namespace@bob'));
    await pumpEventQueue();

    expect(events, ['updated "_x" @bob']);
  });

  test(
      'Given a notification from @bob whose key\'s item id is 65 characters, when it reaches the collection, then an update event with that id is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications.add(fromBob('@alice:$long.$namespace@bob'));
    await pumpEventQueue();

    expect(events, ['updated "$long" @bob']);
  });

  test(
      'Given a notification from @bob whose key\'s item id is "Zz", when it reaches the collection, then an update event with the id "zz" is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications.add(fromBob('@alice:Zz.$namespace@bob'));
    await pumpEventQueue();

    expect(events, ['updated "zz" @bob']);
  });

  test(
      'Given a query watch over an item @bob shares under the id "zz", when notifications from @bob arrive for "Zz" and "ZZ", then every snapshot holds that item once',
      () async {
    seed('cached:@alice:zz.$namespace@bob', 'from bob');
    final c = await todos();
    final snapshots = <List<String>>[];
    final watching = c.query().watch().listen(
        (l) => snapshots.add([for (final i in l) '${i.id} ${i.owner}']));
    addTearDown(watching.cancel);
    await pumpEventQueue();

    notifications
      ..add(fromBob('@alice:Zz.$namespace@bob', value: envelope('from bob')))
      ..add(fromBob('@alice:ZZ.$namespace@bob', value: envelope('from bob')));
    await pumpEventQueue();

    expect(snapshots, isNotEmpty);
    expect(snapshots, everyElement(['zz @bob']));
  });

  test(
      'Given getDescendant has returned an item through the ancestor id "abcd", when it is called with the ancestor id "ABCD", then it opens no further sub-collection',
      () async {
    final opened = stubNotificationService();
    final c = await todos();
    final parent = await c.create(obj: 'p', id: 'abcd');
    await c
        .subCollection<String>(
            parent: parent,
            subName: 'comments',
            defaultExpiration: const Duration(days: 1))
        .create(obj: 'leaf', id: 'c1');
    Future<CItem<String>?> descendant(String ancestorId) =>
        c.getDescendant<String>(ancestry: [
          CAncestor(id: ancestorId, subName: 'comments', owner: alice)
        ], id: 'c1', owner: alice, leafExpiration: const Duration(days: 1));
    expect((await descendant('abcd'))?.id, 'c1');
    final openedBefore = opened();

    final item = await descendant('ABCD');

    expect(item?.id, 'c1');
    expect(opened(), openedBefore,
        reason: 'no further notification subscription is opened');
  });

  test(
      'Given getDescendant has returned an item through the subName "comments", when it is called with the subName "COMMENTS", then it opens no further sub-collection',
      () async {
    final opened = stubNotificationService();
    final c = await todos();
    final parent = await c.create(obj: 'p', id: 'p1');
    await c
        .subCollection<String>(
            parent: parent,
            subName: 'comments',
            defaultExpiration: const Duration(days: 1))
        .create(obj: 'leaf', id: 'c1');
    Future<CItem<String>?> descendant(String subName) =>
        c.getDescendant<String>(
            ancestry: [CAncestor(id: 'p1', subName: subName, owner: alice)],
            id: 'c1',
            owner: alice,
            leafExpiration: const Duration(days: 1));
    expect((await descendant('comments'))?.id, 'c1');
    final openedBefore = opened();

    final item = await descendant('COMMENTS');

    expect(item?.id, 'c1');
    expect(opened(), openedBefore,
        reason: 'no further notification subscription is opened');
  });

  test(
      'Given a notification from @bob whose key has two segments before the namespace, when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:a.b.$namespace@bob'))
      ..add(fromBob(control));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
    final warnings = logs.at('WARNING').where((m) => m.contains('"a.b"'));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('@bob'));
  });

  test(
      'Given a notification from @bob whose key\'s item id is "x@bob", when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:x@bob.$namespace@bob'))
      ..add(fromBob(control));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
  });

  test(
      'Given a notification from @bob whose key\'s item id is "x@alice:y", when it reaches the collection, then no event is emitted',
      () async {
    final c = await todos();
    final events = eventsOf(c);

    notifications
      ..add(fromBob('@alice:x@alice:y.$namespace@bob'))
      ..add(fromBob(control));
    await pumpEventQueue();

    expect(events, [controlUpdated]);
  });
}
