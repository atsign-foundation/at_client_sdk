@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'exported_surface.dart';

/// T6.3: nothing but `dart:js_interop` types crosses the exported surface.
///
/// A member carrying member-level `@JSExport()` that takes or returns a Dart
/// `Future`, `Stream`, `List`, `Uint8List` or any other Dart type compiles,
/// then fails or hangs in JS, so the check reads the sources.

const _jsTypes = {
  'JSAny',
  'JSObject',
  'JSString',
  'JSNumber',
  'JSBoolean',
  'JSFunction',
  'JSPromise',
  'JSArray',
  'JSUint8Array',
  'JSExportedDartFunction',
  'JSBigInt',
};

/// Whether [type] is `void` or a `dart:js_interop` type whose type arguments
/// are too.
bool _isJsType(String type) {
  final t = type.trim().replaceFirst(RegExp(r'\?$'), '');
  if (t == 'void') return true;
  final m = RegExp(r'^(\w+)(?:<(.+)>)?$').firstMatch(t);
  if (m == null || !_jsTypes.contains(m.group(1))) return false;
  final args = m.group(2);
  return args == null || splitTopLevel(args).every(_isJsType);
}

/// Each exported member of [source] that takes or returns a non-JS type.
List<String> _violations(String source) => [
      for (final m in exportedMembers(source))
        for (final type in [m.returns, ...m.params])
          if (!_isJsType(type)) '${m.owner}.${m.name}: $type'
    ];

void main() {
  final sources = {
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };

  test('every member carrying @JSExport takes and returns JS types only', () {
    final exported = {for (final s in sources.values) ...exportedMembers(s)};
    final names = <String, Set<String>>{};
    for (final m in exported) {
      (names[m.owner] ??= <String>{}).add(m.name);
    }
    expect(names, {
      'BridgeSession': {
        'notify',
        'subscribe',
        'status',
        'onStatus',
        'collection',
        'otp',
        'pendingEnrollments',
        'approve',
        'deny',
        'close',
      },
      'BridgeCollection': {
        'create',
        'get',
        'list',
        'query',
        'update',
        'share',
        'remove',
        'watch',
      },
      'BridgeEntry': {'create'},
    });

    for (final MapEntry(:key, :value) in sources.entries) {
      expect(_violations(value), isEmpty, reason: key);
    }
  });

  test('the check flags Dart types on a member-level @JSExport member', () {
    const bad = '''
/*
@JSExport()
class CommentedOut { Future<void> ignored() async {} }
*/
class Leaky {
  @JSExport()
  Future<void> a() async {}
  @JSExport()
  JSPromise<JSAny?> b(List<int> x) => throw 0;
  @JSExport()
  Stream<int> c([JSAny? y = null]) => throw 0;
  @JSExport()
  JSPromise<Uint8List> d() => throw 0;
  @JSExport()
  JSFunction e(JSAny? ok, Object other) => throw 0;
  @JSExport()
  Future<String> get badGetter => throw 0;
  @JSExport()
  set badSetter(List<int> v) {}
  @JSExport()
  String badField = r\'\'\'
    @JSExport() class InsideRaw { Future<void> ignored() async {} }
  \'\'\';
  @JSExport()
  final List<int> badFinalField = const [];
  @JSExport()
  var untypedField = 1;
  @JSExport()
  JSPromise<JSArray<JSString>> fine(JSAny? a, [JSAny? b = null]) => throw 0;
  @JSExport()
  void alsoFine(JSFunction f) {}
  // Not annotated, so not exported.
  Future<void> hidden() async {}
  static Future<void> hiddenStatic() async {}
}
''';
    expect(_violations(bad), [
      'Leaky.a: Future<void>',
      'Leaky.b: List<int>',
      'Leaky.c: Stream<int>',
      'Leaky.d: JSPromise<Uint8List>',
      'Leaky.e: Object',
      'Leaky.badGetter: Future<String>',
      'Leaky.badSetter: List<int>',
      'Leaky.badField: String',
      'Leaky.badFinalField: List<int>',
      'Leaky.untypedField: dynamic',
    ]);
  });

  test('the scanner reads extends, implements, quoted names and CRLF', () {
    const source = 'class Base {}\r\n'
        'class Sub extends Base implements Other {\r\n'
        "  @JSExport('renamed')\r\n"
        '  Future<void> a() async {}\r\n'
        '  @JSExport("quoted")\r\n'
        '  Future<void> get b => throw 0;\r\n'
        '  @JSExport()\r\n'
        '  set c(List<int> v) {}\r\n'
        "  @JSExport()\r\n"
        "  String d = 'a } brace in a string';\r\n"
        '}\r\n';
    expect(_violations(source), [
      'Sub.renamed: Future<void>',
      'Sub.quoted: Future<void>',
      'Sub.c: List<int>',
      'Sub.d: String',
    ]);
    expect(exportedSurface(source), {
      'Sub': ['c', 'd', 'quoted', 'renamed'],
    });
  });

  test('the check flags a class-level @JSExport', () {
    const bad = '''
@JSExport()
class Leaky {
  JSPromise<JSAny?> fine() => throw 0;
}
''';
    expect(classLevelExports(bad), ['Leaky']);
  });

  test('no class carries a class-level @JSExport', () {
    for (final MapEntry(:key, :value) in sources.entries) {
      expect(classLevelExports(value), isEmpty, reason: key);
    }
  });

  test('member-level @JSExport appears only in lib/src/js/bridge.dart', () {
    expect(
        sources.entries
            .where((e) => exportedMembers(e.value).isNotEmpty)
            .map((e) => e.key),
        ['lib/src/js/bridge.dart']);
  });
}
