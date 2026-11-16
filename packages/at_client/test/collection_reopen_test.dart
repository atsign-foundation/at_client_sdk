import 'dart:typed_data';

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
  /// none) followed by '+'-separated flags `data`, `sweep`, `upper` (spell
  /// the namespace in mixed case) and `typeTag:<t>`.
  Future<AtCollection<_Todo>> open(String spec) {
    final tag = spec.split('+').first;
    final typeTag = RegExp(r'typeTag:(\w+)').firstMatch(spec)?.group(1);
    return client.collection<_Todo>(
        spec.contains('+upper') ? 'Notes.Wavi' : ns, const Duration(days: 1),
        eventSource:
            spec.contains('+data') ? EventSource.data : EventSource.both,
        fromJson: typeTag == null ? null : (m) => _Todo(),
        typeTag: typeTag,
        writeTypeTag: tag == '-' ? null : tag,
        cleanupOrphansOnCreation: spec.contains('+sweep'));
  }

  Matcher refused(String held, String asked) => isA<ArgumentError>().having(
      (e) => e.message,
      'message',
      allOf(contains(ns),
          contains('stamping "$held" on a new _Todo, not "$asked"')));

  Matcher badArgs() => isA<ArgumentError>()
      .having((e) => e.message, 'message', isNot(contains('already open')));

  Matcher stamping(String tag) => isA<AtCollection>()
      .having((c) => c.draft(obj: _Todo(), id: 't1').type, 'draft type', tag);

  final cases = <(String, String, String, Matcher Function(AtCollection))>[
    ('-', 'x', 'a refusal', (_) => refused('n/a', 'x')),
    ('x', '-', 'a refusal', (_) => refused('x', 'n/a')),
    ('x', 'y', 'a refusal naming both', (_) => refused('x', 'y')),
    ('x', 'y+sweep', 'a refusal', (_) => refused('x', 'y')),
    ('x', 'y+data', 'a refusal', (_) => refused('x', 'y')),
    ('x', 'y+upper', 'a refusal', (_) => refused('x', 'y')),
    ('x', 'x+data', 'a separate instance', (a) => isNot(same(a))),
    ('x', 'x', 'the same instance', (a) => same(a)),
    ('x', 'x+upper', 'the same instance', (a) => same(a)),
    ('-+typeTag:todo', '-', 'the same instance', (a) => same(a)),
    ('-+typeTag:todo', 'x', 'the same instance', (a) => same(a)),
    ('-+typeTag:todo', 'todo', 'a stamping one', (_) => stamping('todo')),
    ('todo', '-+typeTag:todo', 'a stamping one', (_) => stamping('todo')),
    ('x', '-+typeTag:todo', 'a refusal', (_) => refused('x', 'todo')),
    ('x', ' ', 'ArgumentError, not a refusal', (_) => badArgs()),
    ('x', 'z+typeTag:y', 'ArgumentError, not a refusal', (_) => badArgs()),
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

  test(
      'Given an open that failed to register its factory, when the namespace '
      'is opened again without tags, then a collection is handed out',
      () async {
    AtCollection.registerFactory<_Other>((m) => _Other(), typeTag: 'clash');
    await expectLater(open('-+typeTag:clash'), throwsStateError);
    expect((await open('-')).draft(obj: _Todo(), id: 't1').type, 'n/a');
  });

  test(
      'Given a namespace opened in mixed case, when the collection is handed '
      'out, then its namespace is lower-cased', () async {
    expect((await open('x+upper')).namespace, ns);
  });

  test(
      'Given a byte collection open with writeTypeTag x, when it is reopened '
      'with none, then the same instance is returned', () async {
    final a = await client.collection<Uint8List>(ns, const Duration(days: 1),
        writeTypeTag: 'x');
    expect(await client.collection<Uint8List>(ns, const Duration(days: 1)),
        same(a));
  });
}

class _Todo {}

class _Other {}
