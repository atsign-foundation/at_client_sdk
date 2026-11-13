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

  tearDown(() => client.stop());

  Future<AtCollection<String>> open(String? tag,
          {EventSource eventSource = EventSource.both, bool sweep = false}) =>
      client.collection<String>(ns, day,
          eventSource: eventSource,
          writeTypeTag: tag,
          cleanupOrphansOnCreation: sweep);

  group('reopening a collection with another writeTypeTag', () {
    test(
        'Given a collection open with no writeTypeTag, when it is reopened '
        'with x, then StateError is thrown', () async {
      await open(null);
      await expectLater(open('x'), throwsStateError);
    });

    test(
        'Given a collection open with x, when it is reopened with none, '
        'then StateError is thrown', () async {
      await open('x');
      await expectLater(open(null), throwsStateError);
    });

    test(
        'Given a collection open with x, when it is reopened with y, '
        'then StateError is thrown naming the namespace and both tags',
        () async {
      await open('x');
      await expectLater(
          open('y'),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              allOf(contains(ns), contains('x'), contains('y')))));
    });

    test(
        'Given a collection open with x, when it is reopened with x, '
        'then the same instance is returned', () async {
      final first = await open('x');
      expect(await open('x'), same(first));
    });

    test(
        'Given a collection open with x, when it is reopened with y and '
        'cleanupOrphansOnCreation, then StateError is thrown and the first '
        'instance stays cached', () async {
      final first = await open('x');
      await expectLater(open('y', sweep: true), throwsStateError);
      expect(await open('x'), same(first));
    });

    test(
        'Given a collection open with x, when another eventSource is opened '
        'with y, then it is a separate slot and nothing throws', () async {
      final both = await open('x');
      final data = await open('y', eventSource: EventSource.data);
      expect(data, isNot(same(both)));
      expect(data.writeTypeTag, 'y');
    });
  });
}
