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

/// [source] without line/block comments (including nested `/* ... */`) and
/// string literals (single-line, multiline, and raw), so braces, quotes, and
/// `@JSExport` in them cannot confuse the scan.
String _stripped(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    // Line comment
    if (i + 1 < n && source[i] == '/' && source[i + 1] == '/') {
      i += 2;
      while (i < n && source[i] != '\n') {
        i++;
      }
      continue;
    }
    // Nested block comment
    if (i + 1 < n && source[i] == '/' && source[i + 1] == '*') {
      i += 2;
      var depth = 1;
      while (i < n && depth > 0) {
        if (i + 1 < n && source[i] == '/' && source[i + 1] == '*') {
          depth++;
          i += 2;
        } else if (i + 1 < n && source[i] == '*' && source[i + 1] == '/') {
          depth--;
          i += 2;
        } else {
          if (source[i] == '\n') out.write('\n');
          i++;
        }
      }
      out.write(' ');
      continue;
    }
    // Raw string: r'...' / r"..." / r'''...''' / r"""..."""
    if (source[i] == 'r' &&
        i + 1 < n &&
        (source[i + 1] == '\'' || source[i + 1] == '"')) {
      final quote = source[i + 1];
      final triple =
          i + 3 < n && source[i + 2] == quote && source[i + 3] == quote;
      final delim = triple ? quote * 3 : quote;
      i += 1 + delim.length;
      while (i < n && !source.startsWith(delim, i)) {
        if (!triple && source[i] == '\n') break;
        i++;
      }
      if (source.startsWith(delim, i)) i += delim.length;
      out.write("''");
      continue;
    }
    // Regular or multiline string: '...' / "..." / '''...''' / """..."""
    if (source[i] == '\'' || source[i] == '"') {
      final quote = source[i];
      final triple =
          i + 2 < n && source[i + 1] == quote && source[i + 2] == quote;
      final delim = triple ? quote * 3 : quote;
      i += delim.length;
      while (i < n && !source.startsWith(delim, i)) {
        if (source[i] == r'\' && i + 1 < n) {
          i += 2;
          continue;
        }
        if (!triple && source[i] == '\n') break;
        i++;
      }
      if (source.startsWith(delim, i)) i += delim.length;
      out.write("''");
      continue;
    }
    out.write(source[i]);
    i++;
  }
  return out.toString();
}

/// The members of every `@JSExport` class in [source] as `Class.member`
/// signatures: `(name, returnType, parameterTypes)`.
List<({String owner, String name, String returns, List<String> params})>
    _exportedMembers(String source) {
  final code = _stripped(source);
  final members =
      <({String owner, String name, String returns, List<String> params})>[];
  final classes = RegExp(
    r'@JSExport\([^)]*\)(?:\s*@\w+(?:\([^)]*\))?)*\s*(?:(?:abstract|final|base|interface)\s+)*class\s+(\w+)[^{]*\{',
  ).allMatches(code);
  for (final c in classes) {
    final owner = c.group(1)!;
    var depth = 1;
    var i = c.end;
    final start = i;
    while (i < code.length && depth > 0) {
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
      final parsed = _parseMember(owner, raw);
      if (parsed != null) members.add(parsed);
    }
  }
  return members;
}

({String owner, String name, String returns, List<String> params})?
    _parseMember(String owner, String raw) {
  var text = _signature(raw);
  if (text.isEmpty) return null;
  // Drop leading annotations like `@override`.
  text = text.replaceFirst(RegExp(r'^(?:@\w+(?:\([^)]*\))?\s+)+'), '');
  // Drop member modifiers that are not types.
  text = text.replaceFirst(RegExp(r'^(?:external|static|late)\s+'), '');
  if (text.startsWith('$owner(') ||
      text.startsWith('$owner.') ||
      text.startsWith('factory ')) {
    return null;
  }
  final method = RegExp(r'^(?:(.+?)\s+)?(\w+)\s*\((.*)\)$').firstMatch(text);
  if (method != null) {
    final prefix = method.group(1)?.trim();
    final name = method.group(2)!;
    if (name == owner || name.startsWith('_')) return null;
    if (prefix == 'set' || prefix == 'void set') {
      return (
        owner: owner,
        name: name,
        returns: 'void',
        params: _parameterTypes(method.group(3)!),
      );
    }
    return (
      owner: owner,
      name: name,
      returns: prefix ?? 'dynamic',
      params: _parameterTypes(method.group(3)!),
    );
  }
  final getter = RegExp(r'^(?:(.+?)\s+)?get\s+(\w+)$').firstMatch(text);
  if (getter != null) {
    final name = getter.group(2)!;
    if (name.startsWith('_')) return null;
    return (
      owner: owner,
      name: name,
      returns: getter.group(1)?.trim() ?? 'dynamic',
      params: const [],
    );
  }
  // Field declaration (final, const, var, or typed), with optional initializer.
  final decl = text.replaceFirst(RegExp(r'\s*=.*$'), '').trim();
  final field =
      RegExp(r'^(?:(final|const|var)\s+)?(?:(.+?)\s+)?(\w+)$').firstMatch(decl);
  if (field != null) {
    final qualifier = field.group(1);
    final type = field.group(2)?.trim();
    final name = field.group(3)!;
    if (name.startsWith('_')) return null;
    if (qualifier == null && type == null) return null;
    return (
      owner: owner,
      name: name,
      returns: type ?? 'dynamic',
      params: const [],
    );
  }
  return null;
}

/// [raw] up to the parenthesis that closes its parameter list, so a
/// constructor's initializers and a body modifier like `async` are dropped.
String _signature(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  var i = 0;
  while (true) {
    final open = text.indexOf('(', i);
    if (open < 0) return text;
    var depth = 0;
    var close = -1;
    for (var j = open; j < text.length; j++) {
      if (text[j] == '(') depth++;
      if (text[j] == ')' && --depth == 0) {
        close = j;
        break;
      }
    }
    if (close < 0) return text;
    final after = text.substring(close + 1);
    if (after.isEmpty ||
        RegExp(r'^(?:\s+(?:async|sync)\*?)?(?:\s*(?:\{|=>|;|:)|$)')
                .hasMatch(after) &&
            !RegExp(r'\bFunction\s*$').hasMatch(text.substring(0, open))) {
      return text.substring(0, close + 1);
    }
    i = close + 1;
  }
}

/// The declared type of each parameter in [list] (`JSAny? a, [JSAny? b = null]`).
List<String> _parameterTypes(String list) => [
      for (final raw
          in _splitTopLevel(list.replaceAll(RegExp(r'[\[\]{}]'), '')))
        if (raw.trim().isNotEmpty)
          raw
              .trim()
              .replaceFirst(RegExp(r'^required\s+'), '')
              .replaceFirst(RegExp(r'\s*=.*$'), '')
              .trim()
              .replaceFirst(RegExp(r'\s*\w+$'), '')
              .trim()
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
      'BridgeEntry'
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
    expect(exported.where((m) => m.owner == 'BridgeEntry').map((m) => m.name),
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
/*
@JSExport()
class CommentedOut { Future<void> ignored() async {} }
*/
@JSExport()
class Leaky {
  Future<void> a() async {}
  JSPromise<JSAny?> b(List<int> x) => throw 0;
  Stream<int> c([JSAny? y = null]) => throw 0;
  JSPromise<Uint8List> d() => throw 0;
  JSFunction e(JSAny? ok, Object other) => throw 0;
  Future<String> get badGetter => throw 0;
  set badSetter(List<int> v) {}
  String badField = r\'\'\'
    @JSExport() class InsideRaw { Future<void> ignored() async {} }
  \'\'\';
  final List<int> badFinalField = const [];
  var untypedField = 1;
  JSPromise<JSArray<JSString>> fine(JSAny? a, [JSAny? b = null]) => throw 0;
  void alsoFine(JSFunction f) {}
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

  test('no exported class is declared outside lib/src/js/bridge.dart', () {
    expect(
        sources.entries
            .where((e) => e.value.contains('@JSExport'))
            .map((e) => e.key),
        ['lib/src/js/bridge.dart']);
  });
}
