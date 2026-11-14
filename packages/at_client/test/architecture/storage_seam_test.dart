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
};

/// The shape of a `dart:io` name that opens a connection or starts a process:
/// every socket kind (`Socket`, `RawSocket`, `RawDatagramSocket`,
/// `ServerSocket`, `WebSocket`, ...), every `Http` class, `Process` and the
/// address lookups. `dart:io` stays importable for files, so the names are
/// what keeps a storage off the network.
final _remoteShape = RegExp(r'^(?:\w*Socket\w*|Http[A-Z]\w*|'
    r'Process(?:[A-Z]\w*)?|InternetAddress\w*|NetworkInterface)$');

bool _isRemoteName(String name) =>
    _remoteSide.contains(name) || _remoteShape.hasMatch(name);

/// Rule A7 in docs/architecture/invariants.md: an `AtClientStorage` is storage
/// on the device. It holds no connection, sends nothing to an atServer and
/// decides no routing.
void main() {
  late String pins;
  late Map<String, String> storageSources;
  late Map<String, List<String>> importsUnderStorage;
  late Map<String, String> packageSources;

  setUpAll(() async {
    final barrel = await Isolate.resolvePackageUri(
        Uri.parse('package:at_client/at_client.dart'));
    final lib = p.dirname(barrel!.toFilePath());
    pins = p.join(p.dirname(lib), 'test', 'architecture', 'pins');
    storageSources = _sourcesUnder(p.join(lib, 'src', 'storage'), from: lib);
    importsUnderStorage = {
      for (final MapEntry(key: path, value: source) in storageSources.entries)
        path: _imports(source, from: path),
    };
    final packages = p.dirname(p.dirname(lib));
    packageSources = {
      for (final dir in Directory(packages).listSync().whereType<Directory>())
        if (Directory(p.join(dir.path, 'lib')).existsSync())
          ..._sourcesUnder(p.join(dir.path, 'lib'), from: packages),
    };
  });

  test('the import check flags a storage file that imports the remote side',
      () {
    expect(
        _importOffenders({
          'src/storage/x.dart': [
            'package:at_client/src/client/remote_secondary.dart',
            'package:hive/hive.dart',
          ],
        }, [
          'package:hive/',
          'dart:'
        ]),
        [
          'src/storage/x.dart imports '
              'package:at_client/src/client/remote_secondary.dart'
        ],
        reason: 'a check that never fires is green for every import there is');
    expect(
        _imports(
            "import 'a.dart' if (dart.library.io) "
            "'package:at_client/src/client/remote_secondary.dart';\n"
            "// import 'package:at_lookup/at_lookup.dart';\n",
            from: 'src/storage/x.dart'),
        [
          'package:at_client/src/storage/a.dart',
          'package:at_client/src/client/remote_secondary.dart'
        ],
        reason: 'a conditional import names both its libraries, and a '
            'commented-out import names none');
  });

  test('a storage file imports only what a store on the device needs', () {
    expect(importsUnderStorage.length, greaterThanOrEqualTo(9),
        reason: 'the walk must reach every storage file');
    expect(importsUnderStorage['src/storage/hive/hive_at_client_storage.dart'],
        contains('package:hive/hive.dart'));
    expect(
        _importOffenders(
            importsUnderStorage, _pin(pins, 'storage_imports.txt')),
        isEmpty,
        reason: _importsReason);
    expect(
        _importOffenders({
          'src/storage/x.dart': ['dart:html', 'dart:js_interop'],
        }, _pin(pins, 'storage_imports.txt')),
        hasLength(2),
        reason: 'the pin names each dart: library a storage uses, not all');
  });

  test('the class check follows subclasses and skips comments', () {
    expect(
        _storageClasses({
          'a.dart': 'abstract class Base implements AtClientStorage {}\n',
          'b.dart': 'class Leaf extends Base with Other {}\n'
              '/// class Doc extends AtClientStorage {}\n',
          'c.dart': 'class Unrelated {}\n',
        }),
        {'Base', 'Leaf'});
  });

  test('the class check finds mixin applications, extension types and '
      'headers with a record type', () {
    expect(
        _storageClasses({
          'a.dart': 'class Applied = Object with Impl implements '
              'AtClientStorage;\n',
          'b.dart': 'extension type Wrapped(Object o) implements '
              'AtClientStorage {}\n',
          'c.dart': 'class Recorded extends Box<({int a})> '
              'implements AtClientStorage {}\n',
          'd.dart': 'mixin class Mixed implements AtClientStorage {}\n',
          'e.dart': 'extension type Holder(AtClientStorage s) {}\n'
              "const text = 'class Quoted implements AtClientStorage {}';\n",
        }),
        {'Applied', 'Wrapped', 'Recorded', 'Mixed'},
        reason: 'an extension type that only holds a storage, or a class '
            'named inside a string, implements nothing');
  });

  test('the storage classes are the reviewed set', () {
    expect(packageSources.length, greaterThan(400),
        reason: "the walk must reach every package's lib/");
    expect(_storageClasses(packageSources),
        _pin(pins, 'storage_backends.txt').toSet(),
        reason: _backendsReason);
  });

  test('the member check finds the constructor AtClientStorageBase declares',
      () {
    expect(
        _constructorsAndStatics('AtClientStorageBase',
            storageSources['src/storage/at_client_storage.dart']!),
        isNotEmpty,
        reason: 'a check that finds no constructor there cannot see one');
  });

  test('the member check sees annotated members and members after a brace in '
      'a string or comment', () {
    expect(
        _constructorsAndStatics(
            'S',
            'abstract class S<T extends ({int a})> {\n'
                '  @visibleForTesting static S? override;\n'
                "  String get open => '{'; // {\n"
                r"  String get tag => '${'}'}';" '\n'
                '  /* { */ factory S.memory() = M;\n'
                '  @Deprecated(\n'
                "    'gone',\n"
                '  )\n'
                '  S.named();\n'
                '  void f() { if (true) {} }  static int n = 0;\n'
                '}\n'
                'class Other { static int m = 0; }\n'),
        [
          'static S? override;',
          'factory S.memory() = M;',
          'S.named();',
          'static int n = 0;',
        ]);
  });

  test('AtClientStorage declares no constructor, factory or static member', () {
    expect(
        _constructorsAndStatics('AtClientStorage',
            storageSources['src/storage/at_client_storage.dart']!),
        isEmpty,
        reason: _membersReason);
  });

  test('the name check flags a storage file that names the remote side', () {
    expect(
        _remoteNames({
          'src/storage/x.dart': 'final RemoteSecondary remote;\n'
              '/// An AtLookUp named in a doc comment.\n',
        }),
        ['src/storage/x.dart names RemoteSecondary']);
    expect(
        _remoteNames({
          'src/storage/y.dart':
              "final s = await RawSocket.connect('example.invalid', 64);\n"
                  'RawSecureSocket? secure; RawDatagramSocket? udp;\n'
                  'HttpServer? server; Process? process;\n'
                  "final f = File('x'); final d = Directory('y');\n",
        }),
        unorderedEquals([
          'src/storage/y.dart names RawSocket',
          'src/storage/y.dart names RawSecureSocket',
          'src/storage/y.dart names RawDatagramSocket',
          'src/storage/y.dart names HttpServer',
          'src/storage/y.dart names Process',
        ]),
        reason: 'dart:io is importable for files, so every socket, Http and '
            'Process name must be refused by name');
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

/// The source without its whole-line comments, doc comments included.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Every URI a library's directives name, relative ones resolved to
/// `package:at_client/` from [from], a path under `lib/`.
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
  return 'package:at_client/$path';
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

/// A type declaration's keyword and name: a class (mixin applications
/// included), mixin, enum or extension type.
final _declaration = RegExp(r'\b(?:mixin\s+class|class|mixin|enum|'
    r'extension\s+type)\s+([A-Za-z_$][\w$]*)');

/// Every class, mixin, enum or extension type in [sources] that names
/// `AtClientStorage`, or another class this finds, in its declaration's
/// header.
Set<String> _storageClasses(Map<String, String> sources) {
  final identifier = RegExp(r'[A-Za-z_$][\w$]*');
  final named = <String, Set<String>>{};
  for (final source in sources.values) {
    final code = _blankStringsAndComments(source);
    for (final match in _declaration.allMatches(code)) {
      final (:header, end: _) = _header(code, match.end,
          skipRepresentation: match.group(0)!.startsWith('extension'));
      (named[match.group(1)!] ??= {})
          .addAll(identifier.allMatches(header).map((m) => m.group(0)!));
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
  return storages..remove('AtClientStorage');
}

/// The constructors, factories and static members [className] declares in
/// [source], one line each.
List<String> _constructorsAndStatics(String className, String source) {
  final code = _blankStringsAndComments(source);
  final start = RegExp('\\bclass\\s+${RegExp.escape(className)}\\b')
      .firstMatch(code);
  if (start == null) throw StateError('no class $className in the source');
  final member = RegExp('^(?:const\\s+|external\\s+)*'
      '(?:factory\\b|static\\b|${RegExp.escape(className)}\\s*[.(])');
  final found = <String>[];
  var depth = 0;
  var memberStart = _header(code, start.end).end;
  void endMember(int end) {
    final text = _withoutAnnotations(code.substring(memberStart, end));
    if (member.hasMatch(text)) found.add(text.split('\n').first.trim());
    memberStart = end;
  }

  for (var i = memberStart; i < code.length; i++) {
    switch (code[i]) {
      case '(' || '[' || '{':
        depth++;
      case ')' || ']':
        depth--;
      case '}' when depth == 0:
        endMember(i);
        return found;
      case '}':
        if (--depth == 0) endMember(i + 1);
      case ';' when depth == 0:
        endMember(i + 1);
    }
  }
  return found;
}

/// [member], trimmed, without the annotations it starts with.
String _withoutAnnotations(String member) {
  final name = RegExp(r'^@[\w$.]+\s*');
  var text = member.trim();
  while (name.hasMatch(text)) {
    text = text.substring(name.firstMatch(text)!.end);
    if (text.startsWith('(')) {
      var depth = 0;
      var i = 0;
      do {
        if (text[i] == '(') depth++;
        if (text[i] == ')') depth--;
        i++;
      } while (depth > 0 && i < text.length);
      text = text.substring(i);
    }
    text = text.trimLeft();
  }
  return text;
}

/// The header of the declaration whose name ends at [from] in [code], a
/// source passed through [_blankStringsAndComments]: everything up to the
/// `{` that opens its body or the `;` that ends a mixin application, outside
/// any brackets, so a record type `({int a})` stays in the header. [end] is
/// the index just past that `{` or `;`. With [skipRepresentation], the first
/// parenthesised group, an extension type's representation, is left out.
({String header, int end}) _header(String code, int from,
    {bool skipRepresentation = false}) {
  final header = StringBuffer();
  var depth = 0;
  var skipping = false;
  for (var i = from; i < code.length; i++) {
    final c = code[i];
    if (depth == 0 && (c == '{' || c == ';')) {
      return (header: header.toString(), end: i + 1);
    }
    if (c == '(' && depth == 0 && skipRepresentation) {
      skipping = true;
      skipRepresentation = false;
    }
    if ('([{<'.contains(c)) depth++;
    if (')]}>'.contains(c)) depth--;
    if (!skipping) header.write(c);
    if (skipping && depth == 0) skipping = false;
  }
  return (header: header.toString(), end: code.length);
}

/// [source] with every comment and string literal blanked to spaces, line
/// breaks kept, so that no brace, keyword or name inside one counts.
String _blankStringsAndComments(String source) {
  final units = source.codeUnits.toList();
  final n = source.length;
  void blank(int from, int to) {
    for (var i = from; i < to && i < n; i++) {
      if (units[i] != 0x0A) units[i] = 0x20;
    }
  }

  bool isIdentifier(String c) => RegExp(r'[\w$]').hasMatch(c);

  int blockCommentEnd(int i) {
    var depth = 0;
    while (i < n) {
      if (source.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (source.startsWith('*/', i)) {
        i += 2;
        if (--depth == 0) return i;
      } else {
        i++;
      }
    }
    return n;
  }

  late int Function(int, {required bool interpolation}) codeEnd;

  int stringEnd(int i, {required bool raw}) {
    final quote = source[i];
    final delimiter = source.startsWith(quote * 3, i) ? quote * 3 : quote;
    i += delimiter.length;
    while (i < n) {
      if (source.startsWith(delimiter, i)) return i + delimiter.length;
      if (delimiter.length == 1 && source[i] == '\n') return i;
      if (!raw && source[i] == r'\') {
        i += 2;
      } else if (!raw && source.startsWith(r'${', i)) {
        i = codeEnd(i + 2, interpolation: true);
      } else {
        i++;
      }
    }
    return n;
  }

  codeEnd = (int i, {required bool interpolation}) {
    var depth = 0;
    while (i < n) {
      final c = source[i];
      if (source.startsWith('//', i)) {
        final end = source.indexOf('\n', i);
        final to = end == -1 ? n : end;
        blank(i, to);
        i = to;
      } else if (source.startsWith('/*', i)) {
        final to = blockCommentEnd(i);
        blank(i, to);
        i = to;
      } else if (c == "'" || c == '"') {
        final raw = i > 0 &&
            source[i - 1] == 'r' &&
            (i < 2 || !isIdentifier(source[i - 2]));
        final to = stringEnd(i, raw: raw);
        blank(raw ? i - 1 : i, to);
        i = to;
      } else {
        if (interpolation && c == '{') depth++;
        if (interpolation && c == '}' && depth-- == 0) return i + 1;
        i++;
      }
    }
    return n;
  };

  codeEnd(0, interpolation: false);
  return String.fromCharCodes(units);
}

/// Each name from [_remoteSide], or of [_remoteShape], that a file in
/// [sources] uses outside a whole-line comment.
List<String> _remoteNames(Map<String, String> sources) {
  final identifier = RegExp(r'[A-Za-z_$][\w$]*');
  return [
    for (final MapEntry(key: file, value: source) in sources.entries)
      for (final name in {
        for (final m in identifier.allMatches(_code(source))) m.group(0)!
      }.where(_isRemoteName))
        '$file names $name',
  ];
}

List<String> _pin(String pins, String name) => [
      for (final line in File(p.join(pins, name)).readAsLinesSync())
        if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
          line.trim(),
    ];
