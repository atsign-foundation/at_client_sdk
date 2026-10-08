import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A storage engine and the files in `lib/` allowed to name it.
typedef _Backend = ({List<String> engine, List<String> owners});

const Map<String, _Backend> _backends = {
  'Hive': (
    engine: [
      'package:hive/',
      'package:at_persistence_secondary_server/hive.dart',
      'package:at_persistence_secondary_server/src/impl/hive/',
      'package:at_client/src/storage/hive/',
      'package:at_client/hive.dart',
    ],
    owners: [
      'src/storage/hive/',
      'hive.dart',
      // NOTE: the default seam, which opens Hive for a client given no
      // storage.
      'src/storage/default_storage.dart',
    ],
  ),
  'SQLite': (
    engine: [
      'package:sqlite3/',
      'package:at_persistence_secondary_server/sqlite.dart',
      'package:at_persistence_secondary_server/src/impl/sqlite/',
      'package:at_client/src/storage/sqlite/',
      'package:at_client/sqlite.dart',
    ],
    owners: ['src/storage/sqlite/', 'sqlite.dart', 'src/storage/memory/'],
  ),
};

/// Only a storage backend names its storage engine: the rest of the client
/// works with whatever `AtClientStorage` it is given.
void main() {
  late Map<String, List<String>> importsOf;

  setUpAll(() async {
    final barrel = await Isolate.resolvePackageUri(
        Uri.parse('package:at_client/at_client.dart'));
    importsOf = _importsUnder(p.dirname(barrel!.toFilePath()));
  });

  test('the scan reads every library and resolves relative imports', () {
    expect(importsOf.length, greaterThan(100));
    expect(importsOf['src/storage/hive/hive_at_client_storage.dart'],
        contains('package:hive/hive.dart'));
    expect(importsOf['src/storage/sqlite/sqlite_at_client_storage.dart'],
        contains('package:at_persistence_secondary_server/sqlite.dart'));
    expect(importsOf['src/at_collection/impl/collection_methods_impl.dart'],
        contains('package:at_client/src/at_collection/collections.dart'),
        reason: 'written there as ../collections.dart');
  });

  for (final MapEntry(key: name, value: backend) in _backends.entries) {
    test('only the $name backend names $name', () {
      final offenders = [
        for (final MapEntry(key: file, value: uris) in importsOf.entries)
          if (!backend.owners.any(file.startsWith))
            for (final uri in uris)
              if (backend.engine.any(uri.startsWith)) '$file names $uri',
      ];

      expect(offenders, isEmpty,
          reason: 'storage is the app\'s choice, so outside its backend the '
              'client works with the AtClientStorage it is given');
    });
  }
}

/// Every library under [lib], by its path relative to [lib], with the URIs
/// it imports or exports, relative ones resolved to `package:at_client/`.
Map<String, List<String>> _importsUnder(String lib) {
  final directive =
      RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
  final imports = <String, List<String>>{};
  for (final file in Directory(lib).listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final path = p.posix.joinAll(p.split(p.relative(file.path, from: lib)));
    imports[path] = [
      for (final match in directive.allMatches(file.readAsStringSync()))
        _resolve(match.group(1)!, from: path),
    ];
  }
  return imports;
}

String _resolve(String uri, {required String from}) {
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
  final path = p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
  return 'package:at_client/$path';
}
