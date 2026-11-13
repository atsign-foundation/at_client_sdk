import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// Catalogue: features/at_client/collection_write_type_tag.feature
void main() {
  const ns = 'notes.wavi';
  const at = '@reopen';
  late AtClient client;

  setUp(() async {
    client = await buildAtClient(
        atSign: at,
        namespace: 'wavi',
        preference: AtClientPreference()
          ..namespace = 'wavi'
          ..monitorAutoStart = false,
        secondaryAddressFinder: defaultAtDirectory,
        atKeysIo: noKeysFor(at),
        lookUps: FakeAtServer(atSign: at).lookUps,
        storage: InMemoryAtClientStorage(atSign: at, closedByClient: true));
  });

  tearDown(() async {
    clearFactoriesForTest();
    await client.stop();
  });

  /// Opens the collection described by [spec]: the writeTypeTag ('-' for
  /// none) followed by '+'-separated flags `data`, `sweep` and `typeTag:<t>`.
  Future<AtCollection<_Todo>> open(String spec) {
    final tag = spec.split('+').first;
    final typeTag = RegExp(r'typeTag:(\w+)').firstMatch(spec)?.group(1);
    return client.collection<_Todo>(ns, const Duration(days: 1),
        eventSource:
            spec.contains('+data') ? EventSource.data : EventSource.both,
        fromJson: typeTag == null ? null : (m) => _Todo(),
        typeTag: typeTag,
        writeTypeTag: tag == '-' ? null : tag,
        cleanupOrphansOnCreation: spec.contains('+sweep'));
  }

  Matcher mismatch(String? existing, String? requested) =>
      isA<CollectionTypeTagMismatchException>()
          .having((e) => e.namespace, 'namespace', ns)
          .having((e) => e.existingTag, 'existingTag', existing)
          .having((e) => e.requestedTag, 'requestedTag', requested);

  Matcher stamping(String tag) => isA<AtCollection>()
      .having((c) => c.draft(obj: _Todo(), id: 't1').type, 'draft type', tag);

  final cases = <(String, String, String, Matcher Function(AtCollection))>[
    ('-', 'x', 'a mismatch', (_) => mismatch(null, 'x')),
    ('x', '-', 'a mismatch', (_) => mismatch('x', null)),
    ('x', 'y', 'a mismatch naming both', (_) => mismatch('x', 'y')),
    ('x', 'y+sweep', 'a mismatch', (_) => mismatch('x', 'y')),
    ('x', 'y+data', 'a mismatch', (_) => mismatch('x', 'y')),
    ('x', 'x+data', 'a separate instance', (a) => isNot(same(a))),
    ('x', 'x', 'the same instance', (a) => same(a)),
    ('-+typeTag:todo', 'todo', 'a stamping one', (_) => stamping('todo')),
    ('todo', '-+typeTag:todo', 'a stamping one', (_) => stamping('todo')),
    ('x', ' ', 'ArgumentError', (_) => isA<ArgumentError>()),
    ('x', 'z+typeTag:y', 'ArgumentError', (_) => isA<ArgumentError>()),
  ];

  for (final (first, second, then, want) in cases) {
    test(
        'Given a collection open as [$first], when it is reopened as [$second], '
        'then the outcome is $then, and the first stays cached', () async {
      final a = await open(first);
      final got =
          await Future<Object>.value(open(second)).catchError((Object e) => e);
      expect(got, want(a));
      expect(await open(first), same(a));
    });
  }
}

class _Todo {}
