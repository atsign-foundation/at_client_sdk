@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// T6.3: nothing but `dart:js_interop` types crosses the exported surface.
///
/// A member of a `@JSExport` class that takes or returns a Dart `Future`,
/// `Stream`, `List`, `Uint8List` or any other Dart type compiles, then fails
/// or hangs in JS, so the check reads the sources.

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

/// [source] without comments and string literals, so braces and quotes in
/// them cannot confuse the scan.
String _stripped(String source) => source
    .replaceAll(RegExp(r'//[^\n]*'), '')
    .replaceAll(RegExp(r"'(?:\\.|[^'\\\n])*'|" r'"(?:\\.|[^"\\\n])*"'), "''");

/// The members of every `@JSExport` class in [source] as `Class.member`
/// signatures: `(name, returnType, parameterTypes)`.
List<({String owner, String name, String returns, List<String> params})>
    _exportedMembers(String source) {
  final code = _stripped(source);
  final members =
      <({String owner, String name, String returns, List<String> params})>[];
  final classes =
      RegExp(r'@JSExport\([^)]*\)\s*class\s+(\w+)[^{]*\{').allMatches(code);
  for (final c in classes) {
    final owner = c.group(1)!;
    var depth = 1;
    var i = c.end;
    final start = i;
    while (depth > 0) {
      final ch = code[i++];
      if (ch == '{') depth++;
      if (ch == '}') depth--;
    }
    final body = code.substring(start, i - 1);
    // Keep only depth-0 text of the body: a member's signature, with its
    // block or arrow body dropped.
    final top = StringBuffer();
    var d = 0;
    var paren = 0;
    var arrow = false;
    for (var k = 0; k < body.length; k++) {
      final ch = body[k];
      if (ch == '(') paren++;
      if (ch == ')') paren--;
      if (d == 0 && !arrow && body.startsWith('=>', k)) {
        arrow = true;
        top.write(';');
        continue;
      }
      if (ch == '{' && paren == 0) {
        if (d == 0) top.write(';');
        d++;
        continue;
      }
      if (ch == '}' && paren == 0) {
        d--;
        continue;
      }
      if (ch == ';' && d == 0 && paren == 0) {
        arrow = false;
        top.write(';');
        continue;
      }
      if (d == 0 && !arrow) top.write(ch);
    }
    for (final raw in top.toString().split(';')) {
      final text = _signature(raw);
      final signature = RegExp(r'^(?:static )?(?:([^(]+?) )?(\w+)\s*\((.*)\)$')
          .firstMatch(text);
      if (signature == null || text.startsWith('final ')) continue;
      final name = signature.group(2)!;
      if (name == owner || name.startsWith('_')) continue;
      members.add((
        owner: owner,
        name: name,
        returns: signature.group(1) ?? 'dynamic',
        params: _parameterTypes(signature.group(3)!),
      ));
    }
  }
  return members;
}

/// [raw] up to the parenthesis that closes its parameter list, so a
/// constructor's initializers and a body modifier like `async` are dropped.
String _signature(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final open = text.indexOf('(');
  if (open < 0) return text;
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '(') depth++;
    if (text[i] == ')' && --depth == 0) return text.substring(0, i + 1);
  }
  return text;
}

/// The declared type of each parameter in [list] (`JSAny? a, [JSAny? b]`).
List<String> _parameterTypes(String list) => [
      for (final p in _splitTopLevel(list.replaceAll(RegExp(r'[\[\]{}]'), '')))
        if (p.trim().isNotEmpty)
          p.trim().replaceFirst(RegExp(r'\s*\w+$'), '').trim()
    ];

List<String> _splitTopLevel(String text) {
  final parts = <String>[];
  var depth = 0;
  var from = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '<') depth++;
    if (text[i] == '>') depth--;
    if (text[i] == ',' && depth == 0) {
      parts.add(text.substring(from, i));
      from = i + 1;
    }
  }
  return parts..add(text.substring(from));
}

/// Whether [type] is `void` or a `dart:js_interop` type whose type arguments
/// are too.
bool _isJsType(String type) {
  final t = type.trim().replaceFirst(RegExp(r'\?$'), '');
  if (t == 'void') return true;
  final m = RegExp(r'^(\w+)(?:<(.+)>)?$').firstMatch(t);
  if (m == null || !_jsTypes.contains(m.group(1))) return false;
  final args = m.group(2);
  return args == null || _splitTopLevel(args).every(_isJsType);
}

/// Each exported member of [source] that takes or returns a non-JS type.
List<String> _violations(String source) => [
      for (final m in _exportedMembers(source))
        for (final type in [m.returns, ...m.params])
          if (!_isJsType(type)) '${m.owner}.${m.name}: $type'
    ];

void main() {
  final sources = {
    for (final f in Directory('lib/src/js').listSync().whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };

  test('every member of an exported class takes and returns JS types only', () {
    final exported = {for (final s in sources.values) ..._exportedMembers(s)};
    expect({
      for (final m in exported) m.owner
    }, {
      'BridgeSession',
      'BridgeCollection',
      'AtClientWebBridge'
    }, reason: 'every @JSExport class is scanned');
    expect(
        exported.where((m) => m.owner == 'BridgeSession').map((m) => m.name),
        containsAll([
          'notify',
          'subscribe',
          'status',
          'onStatus',
          'collection',
          'otp',
          'pendingEnrollments',
          'approve',
          'deny',
          'close'
        ]));
    expect(
        exported
            .where((m) => m.owner == 'AtClientWebBridge')
            .map((m) => m.name),
        ['create']);
    expect(
        exported.where((m) => m.owner == 'BridgeCollection').map((m) => m.name),
        containsAll([
          'create',
          'get',
          'list',
          'query',
          'update',
          'share',
          'remove',
          'watch'
        ]));

    for (final MapEntry(:key, :value) in sources.entries) {
      expect(_violations(value), isEmpty, reason: key);
    }
  });

  test('the check flags Dart types on an exported member', () {
    const bad = '''
@JSExport()
class Leaky {
  Future<void> a() async {}
  JSPromise<JSAny?> b(List<int> x) => throw 0;
  Stream<int> c([JSAny? y]) => throw 0;
  JSPromise<Uint8List> d() => throw 0;
  JSFunction e(JSAny? ok, Object other) => throw 0;
  JSPromise<JSArray<JSString>> fine(JSAny? a, [JSAny? b]) => throw 0;
  void alsoFine(JSFunction f) {}
}
''';
    expect(_violations(bad), [
      'Leaky.a: Future<void>',
      'Leaky.b: List<int>',
      'Leaky.c: Stream<int>',
      'Leaky.d: JSPromise<Uint8List>',
      'Leaky.e: Object',
    ]);
  });

  test('no exported class is declared outside lib/src/js/bridge.dart', () {
    expect(
        sources.entries
            .where((e) => e.value.contains('@JSExport'))
            .map((e) => e.key),
        ['lib/src/js/bridge.dart']);
  });
}
