import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _instead = 'To reach the atServer, use useRemoteAtServer on the request, '
    'or AtClientPreference.remoteLocalPref for the whole client; when nothing '
    'durable is wanted, use InMemoryAtClientStorage.';

const _pinMove = 'Moving a pin under test/architecture/pins/, or changing this '
    "test, needs a code owner's review (.github/CODEOWNERS), in a PR of its "
    'own ahead of the change that needs it.';

const _importsReason = 'A7 in docs/architecture/invariants.md: a storage file '
    'imports only what a store on the device needs, as listed in '
    'pins/storage_imports.txt. $_instead $_pinMove';

const _backendsReason = 'A7 in docs/architecture/invariants.md: the classes '
    'that implement AtClientStorage are the reviewed set in '
    'pins/storage_backends.txt, each a store on the device. $_instead '
    '$_pinMove';

const _membersReason = 'A7 in docs/architecture/invariants.md: AtClientStorage '
    'declares no constructor, factory or static member, so the interface never '
    'hands out a storage of its own; a storage is one of the classes in '
    'pins/storage_backends.txt, passed to buildAtClient. $_instead $_pinMove';

const _ownerReason = 'A7 in docs/architecture/invariants.md: a storage uses '
    'the AtClient it is attached to only to know who holds it, through the '
    'members in pins/storage_owner_members.txt; anything more could route an '
    'operation from inside the storage. $_instead $_pinMove';

const _namesReason = 'A7 in docs/architecture/invariants.md: no storage file '
    'names the remote side of a client, such as a RemoteSecondary, an AtLookUp '
    'or a socket. $_instead $_pinMove';

/// Names that belong to the remote side of a client, never to a storage.
const _remoteSide = {
  'RemoteSecondary',
  'getRemoteSecondary',
  'AtLookUp',
  'AtLookupImpl',
  'AtLookUpFactory',
  'executeVerb',
  'Socket',
  'SecureSocket',
  'WebSocket',
  'HttpClient',
};

/// Rule A7 in docs/architecture/invariants.md: an `AtClientStorage` is storage
/// on the device. It holds no connection, sends nothing to an atServer and
/// decides no routing.
///
/// The import, owner and name checks cover every file under
/// `at_client/lib/src/storage/` and every file, in any package, that declares
/// a storage class. Paths are POSIX paths under `packages/`.
void main() {
  late String pins;
  late Map<String, String> packageSources;
  late Map<String, String> storageSources;
  late Map<String, List<String>> importsUnderStorage;

  setUpAll(() async {
    final barrel = await Isolate.resolvePackageUri(
        Uri.parse('package:at_client/at_client.dart'));
    final lib = p.dirname(barrel!.toFilePath());
    pins = p.join(p.dirname(lib), 'test', 'architecture', 'pins');
    final packages = p.dirname(p.dirname(lib));
    packageSources = {
      for (final dir in Directory(packages).listSync().whereType<Directory>())
        if (Directory(p.join(dir.path, 'lib')).existsSync())
          ..._sourcesUnder(p.join(dir.path, 'lib'), from: packages),
    };
    storageSources = _storageScope(packageSources);
    importsUnderStorage = {
      for (final MapEntry(key: path, value: source) in storageSources.entries)
        path: _imports(source, from: path),
    };
  });

  test('the import check flags a storage file that imports the remote side',
      () {
    expect(
        _importOffenders({
          'at_client/lib/src/storage/x.dart': [
            'package:at_client/src/client/remote_secondary.dart',
            'package:hive/hive.dart',
          ],
        }, [
          'package:hive/',
          'dart:'
        ]),
        [
          'at_client/lib/src/storage/x.dart imports '
              'package:at_client/src/client/remote_secondary.dart'
        ],
        reason: 'a check that never fires is green for every import there is');
    expect(
        _imports(
            "import 'a.dart' if (dart.library.io) "
            "'package:at_client/src/client/remote_secondary.dart';\n"
            "// import 'package:at_lookup/at_lookup.dart';\n"
            "/* import 'package:at_lookup/at_lookup.dart'; */\n",
            from: 'at_client/lib/src/storage/x.dart'),
        [
          'package:at_client/src/storage/a.dart',
          'package:at_client/src/client/remote_secondary.dart'
        ],
        reason: 'a conditional import names both its libraries, and a '
            'commented-out import names none');
  });

  test(
      'the storage scope is the storage directory and every file that '
      'declares a storage class, in any package', () {
    expect(
        _storageScope({
          'at_client/lib/src/storage/a.dart': 'class Unrelated {}\n',
          'at_client_web/lib/src/idb.dart':
              'class IdbStorage extends AtClientStorageBase {}\n'
                  'class AtClientStorageBase implements AtClientStorage {}\n',
          'at_client_web/lib/src/other.dart': 'class Other {}\n',
        }).keys,
        unorderedEquals([
          'at_client/lib/src/storage/a.dart',
          'at_client_web/lib/src/idb.dart',
        ]));
    expect(
        _imports("import 'x.dart';\n", from: 'at_client_web/lib/src/idb.dart'),
        ['package:at_client_web/src/x.dart'],
        reason: 'a relative import resolves inside its own package');
  });

  test('a storage file imports only what a store on the device needs', () {
    expect(importsUnderStorage.length, greaterThanOrEqualTo(9),
        reason: 'the walk must reach every storage file');
    expect(
        importsUnderStorage[
            'at_client/lib/src/storage/hive/hive_at_client_storage.dart'],
        contains('package:hive/hive.dart'));
    expect(
        _importOffenders(
            importsUnderStorage, _pin(pins, 'storage_imports.txt')),
        isEmpty,
        reason: _importsReason);
  });

  test('the class check follows subclasses and skips comments', () {
    expect(
        _storageClasses({
          'a.dart': 'abstract class Base implements AtClientStorage {}\n',
          'b.dart': 'class Leaf extends Base with Other {}\n'
              '/// class Doc extends AtClientStorage {}\n'
              '/* class Block extends AtClientStorage {} */\n',
          'c.dart': 'class Unrelated {}\n',
        }),
        {'Base': 'a.dart', 'Leaf': 'b.dart'});
  });

  test('the storage classes are the reviewed set', () {
    expect(packageSources.length, greaterThan(400),
        reason: "the walk must reach every package's lib/");
    expect(_storageClasses(packageSources).keys.toSet(),
        _pin(pins, 'storage_backends.txt').toSet(),
        reason: _backendsReason);
  });

  test('the member check finds the constructor AtClientStorageBase declares',
      () {
    expect(
        _constructorsAndStatics(
            'AtClientStorageBase',
            storageSources[
                'at_client/lib/src/storage/at_client_storage.dart']!),
        isNotEmpty,
        reason: 'a check that finds no constructor there cannot see one');
  });

  test('AtClientStorage declares no constructor, factory or static member', () {
    expect(
        _constructorsAndStatics(
            'AtClientStorage',
            storageSources[
                'at_client/lib/src/storage/at_client_storage.dart']!),
        isEmpty,
        reason: _membersReason);
  });

  test('the owner check flags a member of AtClient off the pinned list', () {
    expect(
        _ownerMembers({
          'at_client/lib/src/storage/x.dart': 'AtClient? _owner;\n'
              'void f(AtClient owner, ({AtClient client, int n}) r) {\n'
              '  owner.getCurrentAtSign();\n'
              '  r.client.keyExists(key, true);\n'
              '  _owner!.put(key, value);\n'
              '}\n',
        }, [
          'getCurrentAtSign'
        ]),
        unorderedEquals([
          'at_client/lib/src/storage/x.dart uses client.keyExists',
          'at_client/lib/src/storage/x.dart uses _owner.put',
        ]));
  });

  test('a storage uses its owner only to know who holds it', () {
    expect(
        _ownerMembers(storageSources, _pin(pins, 'storage_owner_members.txt')),
        isEmpty,
        reason: _ownerReason);
  });

  test('the name check flags a storage file that names the remote side', () {
    expect(
        _remoteNames({
          'at_client/lib/src/storage/x.dart': 'final RemoteSecondary remote;\n'
              '/// An AtLookUp named in a doc comment.\n'
              '/* An AtLookUp named in a block comment,\n'
              '   over two lines. */\n',
        }),
        ['at_client/lib/src/storage/x.dart names RemoteSecondary']);
  });

  test('no storage file names the remote side of a client', () {
    expect(storageSources.length, greaterThanOrEqualTo(9));
    expect(_remoteNames(storageSources), isEmpty, reason: _namesReason);
  });
}

/// Every library under [dir], by its POSIX path relative to [from].
Map<String, String> _sourcesUnder(String dir, {required String from}) => {
      for (final file in Directory(dir).listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          p.posix.joinAll(p.split(p.relative(file.path, from: from))):
              file.readAsStringSync(),
    };

/// The source without its comments: whole-line `//` comments, doc comments
/// included, and `/* */` blocks, each block kept as its newlines so that
/// line positions hold.
String _code(String source) => source
    .replaceAllMapped(RegExp(r'/\*[\s\S]*?\*/'),
        (m) => '\n' * '\n'.allMatches(m.group(0)!).length)
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// The files the storage checks cover, from [sources] keyed by their path
/// under `packages/`: every file under `at_client/lib/src/storage/`, and
/// every file in any package that declares a storage class.
Map<String, String> _storageScope(Map<String, String> sources) {
  final declaring = _storageClasses(sources).values.toSet();
  return {
    for (final MapEntry(key: path, value: source) in sources.entries)
      if (path.startsWith('at_client/lib/src/storage/') ||
          declaring.contains(path))
        path: source,
  };
}

/// Every URI a library's directives name, relative ones resolved to a
/// `package:` URI from [from], a path `<package>/lib/...`.
List<String> _imports(String source, {required String from}) {
  final directive =
      RegExp(r'^\s*(?:import|export|part)\b([^;]*);', multiLine: true);
  final quoted = RegExp(r'''['"]([^'"]+)['"]''');
  return [
    for (final match in directive.allMatches(_code(source)))
      for (final uri in quoted.allMatches(match.group(1)!))
        _resolve(uri.group(1)!, from: from),
  ];
}

String _resolve(String uri, {required String from}) {
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
  final path = p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
  final [package, lib, ...rest] = p.posix.split(path);
  if (lib != 'lib') throw StateError('$from: $uri resolves outside lib/');
  return 'package:$package/${p.posix.joinAll(rest)}';
}

/// Each import in [imports] that no entry of [allowed] admits.
List<String> _importOffenders(
        Map<String, List<String>> imports, List<String> allowed) =>
    [
      for (final MapEntry(key: file, value: uris) in imports.entries)
        for (final uri in uris)
          if (!allowed.any((entry) => _admits(entry, uri)))
            '$file imports $uri',
    ];

bool _admits(String entry, String uri) =>
    entry.endsWith(':') || entry.endsWith('/')
        ? uri.startsWith(entry)
        : uri == entry;

/// Every class, mixin or enum in [sources] that names `AtClientStorage`, or
/// another class this finds, in its declaration's header, with the file that
/// declares it.
Map<String, String> _storageClasses(Map<String, String> sources) {
  final header = RegExp(r'\b(?:class|mixin|enum)\s+(\w+)([^{;]*)\{');
  final identifier = RegExp(r'[A-Za-z_$][\w$]*');
  final named = <String, Set<String>>{};
  final declaredIn = <String, String>{};
  for (final MapEntry(key: path, value: source) in sources.entries) {
    for (final match in header.allMatches(_code(source))) {
      declaredIn[match.group(1)!] = path;
      (named[match.group(1)!] ??= {}).addAll(
          identifier.allMatches(match.group(2)!).map((m) => m.group(0)!));
    }
  }
  final storages = {'AtClientStorage'};
  var grew = true;
  while (grew) {
    grew = false;
    for (final MapEntry(key: name, value: names) in named.entries) {
      if (!storages.contains(name) && names.any(storages.contains)) {
        storages.add(name);
        grew = true;
      }
    }
  }
  storages.remove('AtClientStorage');
  return {for (final name in storages) name: declaredIn[name]!};
}

/// The constructors, factories and static members [className] declares in
/// [source], one line each.
List<String> _constructorsAndStatics(String className, String source) {
  final code = _code(source);
  final start = RegExp('\\bclass\\s+${RegExp.escape(className)}\\b[^{]*\\{')
      .firstMatch(code);
  if (start == null) throw StateError('no class $className in the source');
  final member = RegExp('^\\s*(?:const\\s+|external\\s+)*'
      '(?:factory\\b|static\\b|${RegExp.escape(className)}\\s*[.(])');
  final found = <String>[];
  var depth = 0;
  for (final line in code.substring(start.end).split('\n')) {
    if (depth == 0 && member.hasMatch(line)) found.add(line.trim());
    depth += '{'.allMatches(line).length - '}'.allMatches(line).length;
    if (depth < 0) break;
  }
  return found;
}

/// Each member of an `AtClient` that a file in [sources] reaches, off the
/// [allowed] list. An `AtClient` is a name declared with that type, as a
/// field, a parameter, a local or a record field; a member is what follows
/// `name.`, `name!.` or `name?.`. A client reached through an untyped alias
/// is not seen; review holds that.
List<String> _ownerMembers(Map<String, String> sources, List<String> allowed) {
  final declared = RegExp(r'\bAtClient\??\s+(\w+)');
  return [
    for (final MapEntry(key: file, value: source) in sources.entries)
      for (final use in {
        for (final name in {
          for (final m in declared.allMatches(_code(source))) m.group(1)!
        })
          for (final m in RegExp('\\b${RegExp.escape(name)}[!?]?\\.(\\w+)')
              .allMatches(_code(source)))
            if (!allowed.contains(m.group(1))) '$name.${m.group(1)}',
      })
        '$file uses $use',
  ];
}

/// Each name from [_remoteSide] that a file in [sources] uses outside a
/// comment.
List<String> _remoteNames(Map<String, String> sources) {
  final identifier = RegExp(r'[A-Za-z_$][\w$]*');
  return [
    for (final MapEntry(key: file, value: source) in sources.entries)
      for (final name in {
        for (final m in identifier.allMatches(_code(source))) m.group(0)!
      }.where(_remoteSide.contains))
        '$file names $name',
  ];
}

List<String> _pin(String pins, String name) => [
      for (final line in File(p.join(pins, name)).readAsLinesSync())
        if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
          line.trim(),
    ];
