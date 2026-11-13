import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// Catalogue: features/at_client/collection_write_type_tag.feature
void main() {
  const ns = 'notes.wavi';
  const day = Duration(days: 1);

  late AtClient client;

  setUp(() async {
    client = await buildAtClient(
        atSign: '@reopen',
        namespace: 'wavi',
        preference: AtClientPreference()
          ..namespace = 'wavi'
          ..monitorAutoStart = false,
        secondaryAddressFinder: defaultAtDirectory,
        atKeysIo: noKeysFor('@reopen'),
        lookUps: FakeAtServer(atSign: '@reopen').lookUps,
        storage:
            InMemoryAtClientStorage(atSign: '@reopen', closedByClient: true));
  });

  tearDown(() async {
    clearFactoriesForTest();
    await client.stop();
  });

  Future<AtCollection<String>> open(String? tag,
          {EventSource eventSource = EventSource.both, bool sweep = false}) =>
      client.collection<String>(ns, day,
          eventSource: eventSource,
          writeTypeTag: tag,
          cleanupOrphansOnCreation: sweep);

  Matcher mismatch(String existing, String requested) =>
      throwsA(isA<CollectionTypeTagMismatchException>()
          .having((e) => e.namespace, 'namespace', ns)
          .having((e) => e.existingTag, 'existingTag', existing)
          .having((e) => e.requestedTag, 'requestedTag', requested));

  group('reopening a collection with another effective tag', () {
    test(
        'Given a collection open with no writeTypeTag, when it is reopened '
        'with x, then CollectionTypeTagMismatchException is thrown', () async {
      await open(null);
      await expectLater(
          open('x'), throwsA(isA<CollectionTypeTagMismatchException>()));
    });

    test(
        'Given a collection open with x, when it is reopened with none, '
        'then CollectionTypeTagMismatchException is thrown', () async {
      await open('x');
      await expectLater(
          open(null), throwsA(isA<CollectionTypeTagMismatchException>()));
    });

    test(
        'Given a collection open with x, when it is reopened with y, '
        'then the exception names the namespace and both tags', () async {
      await open('x');
      await expectLater(open('y'), mismatch('x', 'y'));
    });

    test(
        'Given a collection open with x, when it is reopened with x, '
        'then the same instance is returned', () async {
      final first = await open('x');
      expect(await open('x'), same(first));
    });

    test(
        'Given a collection open with x, when it is reopened with y and '
        'cleanupOrphansOnCreation, then the exception is thrown and the first '
        'instance stays cached', () async {
      final first = await open('x');
      await expectLater(open('y', sweep: true), mismatch('x', 'y'));
      expect(await open('x'), same(first));
    });

    test(
        'Given a collection open with x, when another eventSource is opened '
        'with y, then CollectionTypeTagMismatchException is thrown', () async {
      await open('x');
      await expectLater(
          open('y', eventSource: EventSource.data), mismatch('x', 'y'));
    });

    test(
        'Given a collection open with x, when another eventSource is opened '
        'with x, then it is a separate instance', () async {
      final both = await open('x');
      final data = await open('x', eventSource: EventSource.data);
      expect(data, isNot(same(both)));
      expect(data.writeTypeTag, 'x');
    });

    test(
        'Given a collection open with typeTag todo, when it is reopened with '
        'writeTypeTag todo, then a usable collection is returned', () async {
      await client.collection<_Todo>(ns, day,
          fromJson: (m) => _Todo(), typeTag: 'todo');
      final again =
          await client.collection<_Todo>(ns, day, writeTypeTag: 'todo');
      expect(again.draft(obj: _Todo(), id: 't1').type, 'todo');
    });

    test(
        'Given a collection open with writeTypeTag todo, when it is reopened '
        'with typeTag todo, then a usable collection is returned', () async {
      await open('todo');
      final again = await client.collection<String>(ns, day,
          fromJson: (m) => 'todo', typeTag: 'todo');
      expect(again.namespace, ns);
    });
  });

  group('refusing tag arguments before comparing tags', () {
    test(
        'Given a collection open with x, when it is reopened with a blank '
        'writeTypeTag, then ArgumentError is thrown, not a mismatch', () async {
      await open('x');
      await expectLater(open(' '), throwsArgumentError);
    });

    test(
        'Given a collection open with x, when it is reopened with a '
        'writeTypeTag that conflicts with typeTag, then ArgumentError is '
        'thrown, not a mismatch', () async {
      await open('x');
      await expectLater(
          client.collection<_Todo>(ns, day,
              fromJson: (m) => _Todo(), typeTag: 'y', writeTypeTag: 'z'),
          throwsArgumentError);
    });
  });
}

class _Todo {}
