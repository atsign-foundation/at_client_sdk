// Reopening a collection with another type tag:
// features/at_client/collection_write_type_tag.feature, from "Reopening a
// collection" on. Each test name is its scenario's title.

import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/hive_store.dart';
import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

void main() {
  const namespace = 'things.wavi';
  const expiry = Duration(days: 1);
  final throwsMismatch = throwsA(isA<CollectionTypeTagMismatchException>());

  late Directory dir;
  late AtClient client;

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

  setUp(() async {
    clearFactoriesForTest();
    dir = Directory.systemTemp.createTempSync('collection_reopen_');
    AtClientManager.getInstance().reset();
    const atSign = '@reopened';
    client = await buildAtClient(
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
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
    clearFactoriesForTest();
    dir.deleteSync(recursive: true);
  });

  Future<AtCollection<Map<String, dynamic>>> openTyped(String typeTag,
          {EventSource eventSource = EventSource.both}) =>
      client.collection<Map<String, dynamic>>(namespace, expiry,
          eventSource: eventSource, fromJson: (j) => j, typeTag: typeTag);

  test(
      'Given a collection opened with writeTypeTag Todo, when the same client opens it again with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown and the first keeps Todo',
      () async {
    final first = await client.collection<String>(namespace, expiry,
        writeTypeTag: 'Todo');

    await expectLater(
      client.collection<String>(namespace, expiry, writeTypeTag: 'Note'),
      throwsA(isA<CollectionTypeTagMismatchException>()
          .having((e) => e.namespace, 'namespace', namespace)
          .having((e) => e.existingTag, 'existingTag', 'Todo')
          .having((e) => e.requestedTag, 'requestedTag', 'Note')),
    );
    expect(first.writeTypeTag, 'Todo');
    expect(first.draft(obj: 'buy milk').type, 'Todo');
  });

  test(
      'Given a collection opened with factory typeTag Todo, when the same client opens it again with typeTag Note, then CollectionTypeTagMismatchException is thrown',
      () async {
    await openTyped('Todo');

    await expectLater(openTyped('Note'), throwsMismatch);
  });

  test(
      'Given a collection opened with factory typeTag Todo, when the same client opens it again with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown',
      () async {
    await openTyped('Todo');

    await expectLater(
        client.collection<Map<String, dynamic>>(namespace, expiry,
            writeTypeTag: 'Note'),
        throwsMismatch);
  });

  test(
      'Given a collection opened with writeTypeTag Todo, when it is opened from another event source with writeTypeTag Note, then CollectionTypeTagMismatchException is thrown',
      () async {
    await client.collection<String>(namespace, expiry,
        eventSource: EventSource.data, writeTypeTag: 'Todo');

    await expectLater(
        client.collection<String>(namespace, expiry,
            eventSource: EventSource.notifs, writeTypeTag: 'Note'),
        throwsMismatch);
  });

  test(
      'Given a collection opened with writeTypeTag Todo, when it is opened again with Todo, then it gets the open collection',
      () async {
    final first = await client.collection<String>(namespace, expiry,
        writeTypeTag: 'Todo');

    final again = await client.collection<String>(namespace, expiry,
        writeTypeTag: 'Todo');

    expect(identical(first, again), isTrue);
  });

  test(
      'Given a collection opened with factory typeTag Todo, when it is opened again with typeTag Todo, then it gets the open collection',
      () async {
    final first = await openTyped('Todo');

    expect(identical(await openTyped('Todo'), first), isTrue);
  });

  test(
      'Given a collection opened with writeTypeTag Todo, when it is opened again with no tag, then it gets the open collection',
      () async {
    final first = await client.collection<String>(namespace, expiry,
        writeTypeTag: 'Todo');

    final again = await client.collection<String>(namespace, expiry);

    expect(identical(first, again), isTrue);
    expect(again.writeTypeTag, 'Todo');
  });

  test(
      'Given a collection opened with factory typeTag Todo, when it is opened from another event source with no tag, then the new instance stamps Todo',
      () async {
    await openTyped('Todo', eventSource: EventSource.data);

    final other = await client.collection<String>(namespace, expiry,
        eventSource: EventSource.notifs);

    expect(other.writeTypeTag, 'Todo');
    expect(other.draft(obj: 'buy milk').type, 'Todo');
  });

  test(
      'Given an untagged open collection, when it is opened with writeTypeTag Todo, then the open instance adopts Todo',
      () async {
    final untagged = await client.collection<String>(namespace, expiry,
        eventSource: EventSource.data);
    expect(untagged.writeTypeTag, isNull);

    final tagged = await client.collection<String>(namespace, expiry,
        eventSource: EventSource.notifs, writeTypeTag: 'Todo');

    expect(identical(untagged, tagged), isFalse);
    expect(untagged.draft(obj: 'buy milk').type, 'Todo');
  });

  test(
      'Given a collection opened with writeTypeTag Todo, when it is opened again with a blank writeTypeTag, then ArgumentError is thrown',
      () async {
    await client.collection<String>(namespace, expiry, writeTypeTag: 'Todo');

    await expectLater(
        client.collection<String>(namespace, expiry, writeTypeTag: ' '),
        throwsArgumentError);
  });

  test(
      'Given a collection opened with writeTypeTag Todo, when another namespace is opened with Note, then it opens with Note',
      () async {
    await client.collection<String>(namespace, expiry, writeTypeTag: 'Todo');

    final other = await client.collection<String>('others.wavi', expiry,
        writeTypeTag: 'Note');

    expect(other.draft(obj: 'buy milk').type, 'Note');
  });
}
