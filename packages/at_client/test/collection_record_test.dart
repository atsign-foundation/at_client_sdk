// The collection record: features/at_client/collection_write_type_tag.feature,
// from "The collection record" on. Each test name is its scenario's title.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/collections/collections.dart'
    show CollectionRegistry;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/hive_store.dart';
import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAtKey());
    registerFallbackValue(GetRequestOptions());
  });

  const self = '@alice';
  const namespace = 'tasks.app_1.my_apps';
  const recordKey = '__collection.$namespace$self';

  late MockAtClient atClient;
  late StreamController<AtNotification> notifications;
  late CollectionRegistry registry;

  /// This atSign's local store and its atServer, by key name.
  late Map<String, String> local;
  late Map<String, String> remote;

  /// What a remote read throws instead of answering, when set.
  Object? remoteFails;

  /// What a local read throws instead of answering, when set.
  Object? localFails;

  /// Every value put, in order, as (key, value).
  late List<(String, String)> puts;

  /// Lets every other open run before a read answers.
  Future<void> yieldToOthers() => Future<void>(() {});

  setUp(() {
    clearFactoriesForTest();
    atClient = MockAtClient();
    notifications = StreamController<AtNotification>.broadcast();
    registry = CollectionRegistry();
    local = {};
    remote = {};
    remoteFails = null;
    localFails = null;
    puts = [];
    when(() => atClient.atSign).thenReturn(self.toAtsign());
    when(() => atClient.get(any(),
            getRequestOptions: any(named: 'getRequestOptions')))
        .thenAnswer((inv) async {
      await yieldToOthers();
      final key = '${inv.positionalArguments[0]}';
      final options =
          inv.namedArguments[#getRequestOptions] as GetRequestOptions?;
      final isRemote = options?.useRemoteAtServer ?? false;
      final failure = isRemote ? remoteFails : localFails;
      if (failure != null) throw failure;
      final value = (isRemote ? remote : local)[key];
      if (value == null) throw AtKeyNotFoundException('$key not found');
      return AtValue()..value = value;
    });
    when(() => atClient.put(any(), any())).thenAnswer((inv) async {
      final key = '${inv.positionalArguments[0]}';
      final value = inv.positionalArguments[1] as String;
      puts.add((key, value));
      local[key] = value;
      return true;
    });
  });

  tearDown(() async {
    await notifications.close();
  });

  Future<AtCollection<T>> open<T>({
    String? writeTypeTag,
    String? typeTag,
    T Function(Map<String, dynamic>)? fromJson,
    EventSource eventSource = EventSource.notifs,
  }) =>
      registry.open<T>(
        atClient,
        namespace,
        eventSource,
        hasFromJson: fromJson != null,
        typeTag: typeTag,
        writeTypeTag: writeTypeTag,
        build: (tag) => collectionWithInjectedNotifications<T>(
          atClient,
          namespace,
          const Duration(days: 1),
          notifications: notifications.stream,
          fromJson: fromJson,
          typeTag: typeTag,
          writeTypeTag: tag,
        ),
      );

  String record(String tag) => jsonEncode({'v': 1, 'writeTypeTag': tag});

  final throwsMismatch = throwsA(isA<CollectionTypeTagMismatchException>());

  test(
      'Given no collection record and writeTypeTag Todo, when the collection is opened, then a version 1 record with tag Todo is written',
      () async {
    final c = await open<String>(writeTypeTag: 'Todo');

    expect(puts, hasLength(1));
    expect(puts.single.$1, recordKey);
    expect(jsonDecode(puts.single.$2), {'v': 1, 'writeTypeTag': 'Todo'});
    expect(c.writeTypeTag, 'Todo');
  });

  test(
      'Given a record with tag Todo, when the collection is opened with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown',
      () async {
    local[recordKey] = record('Todo');

    await expectLater(
      open<String>(writeTypeTag: 'Note'),
      throwsA(isA<CollectionTypeTagMismatchException>()
          .having((e) => e.namespace, 'namespace', namespace)
          .having((e) => e.recordedTag, 'recordedTag', 'Todo')
          .having((e) => e.requestedTag, 'requestedTag', 'Note')),
    );
    expect(puts, isEmpty);
  });

  test(
      'Given a record with tag Todo, when the collection is opened with writeTypeTag Todo, then it opens and no record is written',
      () async {
    local[recordKey] = record('Todo');

    final c = await open<String>(writeTypeTag: 'Todo');

    expect(c.writeTypeTag, 'Todo');
    expect(puts, isEmpty);
  });

  test(
      'Given a record with tag Todo, when the collection is opened with no tag, then it adopts Todo',
      () async {
    local[recordKey] = record('Todo');

    final c = await open<String>();

    expect(c.writeTypeTag, 'Todo');
    expect(c.draft(obj: 'buy milk').type, 'Todo');
    expect(puts, isEmpty);
  });

  test(
      'Given a record with tag Todo, when the collection is opened with typeTag Note and no writeTypeTag, then CollectionTypeTagMismatchException is thrown',
      () async {
    local[recordKey] = record('Todo');

    await expectLater(
      open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Note'),
      throwsMismatch,
    );
    expect(puts, isEmpty);
  });

  test(
      'Given no collection record, when the collection is opened with no writeTypeTag, then no record is written',
      () async {
    final c = await open<String>();

    expect(c.writeTypeTag, isNull);
    expect(c.draft(obj: 'buy milk').type, 'n/a');
    expect(puts, isEmpty);
  });

  test(
      'Given no collection record, when the collection is opened with typeTag Todo and no writeTypeTag, then no record is written',
      () async {
    final c =
        await open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Todo');

    expect(c.writeTypeTag, isNull);
    expect(puts, isEmpty);
  });

  test(
      'Given an open collection, when it is opened again with a blank writeTypeTag, then ArgumentError is thrown and nothing is written',
      () async {
    await open<String>();

    expect(() => open<String>(writeTypeTag: '  '), throwsArgumentError);
    expect(puts, isEmpty);
  });

  test(
      'Given no local record and a client stopped during the atServer read, when the collection is opened with Todo, then StoppedException is thrown and nothing is written',
      () async {
    remoteFails = StoppedException('the client is stopped');

    await expectLater(
        open<String>(writeTypeTag: 'Todo'), throwsA(isA<StoppedException>()));
    expect(puts, isEmpty);
  });

  test(
      'Given an open collection with writeTypeTag Todo, when it is opened again with Note, then CollectionTypeTagMismatchException is thrown and the instance keeps Todo',
      () async {
    final first = await open<String>(writeTypeTag: 'Todo');

    await expectLater(open<String>(writeTypeTag: 'Note'), throwsMismatch);

    expect(first.writeTypeTag, 'Todo');
    expect(puts, hasLength(1));
  });

  test(
      'Given an open collection with factory typeTag Todo and no record, when it is opened again with typeTag Note, then CollectionTypeTagMismatchException is thrown',
      () async {
    await open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Todo');

    await expectLater(
      open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Note'),
      throwsA(isA<CollectionTypeTagMismatchException>()
          .having((e) => e.recordedTag, 'recordedTag', 'Todo')
          .having((e) => e.requestedTag, 'requestedTag', 'Note')),
    );
    expect(puts, isEmpty);
  });

  test(
      'Given an open collection with factory typeTag Todo and no record, when it is opened again with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown and nothing is written',
      () async {
    await open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Todo');

    await expectLater(
        open<Map<String, dynamic>>(writeTypeTag: 'Note'), throwsMismatch);
    expect(puts, isEmpty);
  });

  test(
      'Given an open collection with factory typeTag Todo and no record, when it is opened again with typeTag Todo, then it gets the open collection',
      () async {
    final first =
        await open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Todo');

    final again =
        await open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Todo');

    expect(identical(first, again), isTrue);
  });

  test(
      'Given an open collection with factory typeTag Todo and no record, when it is opened again with no tag, then it gets the open collection',
      () async {
    final first =
        await open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Todo');

    final again = await open<Map<String, dynamic>>();

    expect(identical(first, again), isTrue);
    expect(puts, isEmpty);
  });

  test(
      'Given an open collection with factory typeTag Todo and no record, when it is opened from another event source with no tag, then the new instance stamps Todo',
      () async {
    await open<Map<String, dynamic>>(fromJson: (j) => j, typeTag: 'Todo');

    final other = await open<String>(eventSource: EventSource.data);

    expect(other.writeTypeTag, 'Todo');
    expect(other.draft(obj: 'buy milk').type, 'Todo');
  });

  test(
      'Given an untagged open collection with no record, when it is opened with writeTypeTag Todo, then the open instance adopts Todo',
      () async {
    final untagged = await open<String>(eventSource: EventSource.data);
    expect(untagged.writeTypeTag, isNull);

    final tagged = await open<String>(writeTypeTag: 'Todo');

    expect(identical(untagged, tagged), isFalse);
    expect(untagged.draft(obj: 'buy milk').type, 'Todo');
  });

  test(
      'Given two opens with Todo and Note at once, when both run, then one gets the collection and the other a mismatch',
      () async {
    final outcomes = await Future.wait([
      for (final tag in ['Todo', 'Note'])
        open<String>(writeTypeTag: tag)
            .then<Object>((c) => c, onError: (Object e) => e),
    ]);

    expect(outcomes.whereType<AtCollection<String>>(), hasLength(1));
    expect(
        outcomes.whereType<CollectionTypeTagMismatchException>(), hasLength(1));
    expect(puts, hasLength(1));
  });

  test(
      'Given no local record and a record with Todo on the atServer, when the collection is opened with Note, then CollectionTypeTagMismatchException is thrown and nothing is written',
      () async {
    remote[recordKey] = record('Todo');

    await expectLater(open<String>(writeTypeTag: 'Note'), throwsMismatch);
    expect(puts, isEmpty);
  });

  test(
      'Given no local record and an atServer that cannot be reached, when the collection is opened with Todo, then the record is claimed locally',
      () async {
    remoteFails = Exception('no route to the atServer');

    final c = await open<String>(writeTypeTag: 'Todo');

    expect(c.writeTypeTag, 'Todo');
    expect(puts.single.$1, recordKey);
    expect(jsonDecode(local[recordKey]!)['writeTypeTag'], 'Todo');
  });

  test(
      'Given a version 2 record with tag Todo and a schema field, when the collection is opened with Todo, then it opens',
      () async {
    local[recordKey] = jsonEncode({
      'v': 2,
      'writeTypeTag': 'Todo',
      'schema': {'type': 'object'},
    });

    final c = await open<String>(writeTypeTag: 'Todo');

    expect(c.writeTypeTag, 'Todo');
    expect(puts, isEmpty);
  });

  group(
      'Given a malformed collection record, when the collection is opened, then FormatException is thrown',
      () {
    final malformed = <String, String>{
      'not json': 'not json',
      'a JSON array': '["Todo"]',
      'no version': '{"writeTypeTag":"Todo"}',
      'version 0': '{"v":0,"writeTypeTag":"Todo"}',
      'a string version': '{"v":"1","writeTypeTag":"Todo"}',
      'no writeTypeTag': '{"v":1}',
      'a blank writeTypeTag': '{"v":1,"writeTypeTag":"  "}',
      'a value over 1 MiB': jsonEncode(
          {'v': 1, 'writeTypeTag': 'Todo', 'pad': 'x' * (1024 * 1024)}),
    };
    for (final MapEntry(key: name, value: value) in malformed.entries) {
      test(name, () async {
        local[recordKey] = value;

        await expectLater(
            open<String>(writeTypeTag: 'Todo'), throwsFormatException);
        expect(puts, isEmpty);
      });
    }

    test('a record on the atServer', () async {
      remote[recordKey] = '{"v":1}';

      await expectLater(
          open<String>(writeTypeTag: 'Todo'), throwsFormatException);
      expect(puts, isEmpty);
    });

    test('a value that is not text', () async {
      when(() => atClient.get(any(),
              getRequestOptions: any(named: 'getRequestOptions')))
          .thenAnswer((_) async => AtValue()..value = 42);

      await expectLater(
          open<String>(writeTypeTag: 'Todo'), throwsFormatException);
      expect(puts, isEmpty);
    });
  });

  test(
      'Given the record cannot be read for another reason, when the collection is opened, then that error is thrown',
      () async {
    final failure = AtDecryptionException('no key to decrypt the record');
    localFails = failure;

    await expectLater(open<String>(writeTypeTag: 'Todo'), throwsA(failure));
    expect(puts, isEmpty);
  });

  test(
      'Given a shared-in record from another atSign with tag Note, when the collection is opened with Todo, then the record is claimed as Todo',
      () async {
    local['$self:__collection.$namespace@bob'] = record('Note');
    local['cached:$self:__collection.$namespace@bob'] = record('Note');

    final c = await open<String>(writeTypeTag: 'Todo');

    expect(c.writeTypeTag, 'Todo');
    expect(puts.single.$1, recordKey);
  });

  test(
      'Given the reserved id __collection, when an item is drafted with it, then ArgumentError is thrown',
      () async {
    final c = await open<String>();

    expect(() => c.draft(obj: 'x', id: '__collection'), throwsArgumentError);
  });

  group(
      'Given a collection record in the local store, when the items are read or a data event for it arrives, then it is not an item',
      () {
    const recordKeys = [
      recordKey,
      'cached:$self:__collection.$namespace@bob',
      '$self:__collection.$namespace@bob',
    ];
    const itemKey = 'abc.$namespace$self';

    test('the scan for items', () async {
      String? scanned;
      when(() => atClient.getAtKeys(regex: any(named: 'regex')))
          .thenAnswer((inv) async {
        scanned = inv.namedArguments[#regex] as String;
        return <AtKey>[];
      });
      final c = await open<String>();

      await c.getItems();

      final regex = RegExp(scanned!);
      for (final key in recordKeys) {
        expect(regex.hasMatch(key), isFalse, reason: key);
      }
      expect(regex.hasMatch(itemKey), isTrue);
    });

    test('a data event', () async {
      final dataEvents = StreamController<DataEvent>.broadcast();
      addTearDown(dataEvents.close);
      when(() => atClient.dataEvents).thenAnswer((_) => dataEvents.stream);
      final c = AtCollection<String>(
        atClient,
        namespace,
        const Duration(days: 1),
        eventSource: EventSource.data,
      );
      final updated = <String>[];
      final sub = c.updates.listen((e) => updated.add(e.id));
      addTearDown(sub.cancel);

      for (final key in [...recordKeys, itemKey]) {
        dataEvents.add(DataUpdated(AtKey.fromString(key)));
      }
      await pumpEventQueue();

      expect(updated, ['abc']);
    });
  });

  group('AtClient.collection', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('collection_record_');
      AtClientManager.getInstance().reset();
    });

    tearDown(() async {
      for (final c
          in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
        await c.stop();
      }
      AtClientManager.getInstance().reset();
      dir.deleteSync(recursive: true);
    });

    AtLookupMuxable offline({
      required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder,
    }) {
      final lookUp = MockAtLookupImpl();
      when(() => lookUp.isConnectionAvailable()).thenReturn(false);
      when(() => lookUp.close()).thenAnswer((_) async {});
      when(() => lookUp.stopNotifications()).thenAnswer((_) async {});
      return lookUp;
    }

    test(
        'Given a record with tag Todo, when AtClient.collection opens it with Note and then with no tag, then the first throws and the second adopts Todo',
        () async {
      const atSign = '@recorded';
      final client = await buildAtClient(
          atSign: atSign,
          namespace: 'wavi',
          preference: AtClientPreference()
            ..hiveStoragePath = dir.path
            ..namespace = 'wavi'
            ..monitorAutoStart = false,
          secondaryAddressFinder: defaultAtDirectory,
          atKeysIo: noKeysFor(atSign),
          lookUps: offline,
          storage: hiveStoreAt(atSign, dir.path));
      // NOTE: a client with no keys cannot encrypt, so the record is put in
      // the clear; the read path is the same.
      await client.put(
          AtKey.fromString('__collection.things.wavi$atSign'), record('Todo'),
          putRequestOptions: PutRequestOptions()..shouldEncrypt = false);

      await expectLater(
          client.collection<String>('things.wavi', const Duration(days: 1),
              writeTypeTag: 'Note'),
          throwsMismatch);
      final c = await client.collection<String>(
          'things.wavi', const Duration(days: 1));
      expect(c.writeTypeTag, 'Todo');
    });

    Future<AtClient> unrecordedClient(String atSign) => buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: AtClientPreference()
          ..hiveStoragePath = dir.path
          ..namespace = 'wavi'
          ..monitorAutoStart = false,
        secondaryAddressFinder: defaultAtDirectory,
        atKeysIo: noKeysFor(atSign),
        lookUps: offline,
        storage: hiveStoreAt(atSign, dir.path));

    test(
        'Given AtClient.collection opened with factory typeTag Todo, when the same client opens it again with typeTag Note, then CollectionTypeTagMismatchException is thrown',
        () async {
      final client = await unrecordedClient('@refactoried');
      await client.collection<Map<String, dynamic>>(
          'things.wavi', const Duration(days: 1),
          fromJson: (j) => j, typeTag: 'Todo');

      await expectLater(
          client.collection<Map<String, dynamic>>(
              'things.wavi', const Duration(days: 1),
              fromJson: (j) => j, typeTag: 'Note'),
          throwsMismatch);
    });
  });
}
