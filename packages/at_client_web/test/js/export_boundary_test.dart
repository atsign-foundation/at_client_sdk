@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

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

/// Every class declaration, its leading annotations (group 1) and its name
/// (group 2). The body starts at the match's `{`.
final _classPattern = RegExp(
  r'((?:@\w+(?:\([^)]*\))?\s*)*)(?:(?:abstract|final|base|interface|sealed|mixin)\s+)*class\s+(\w+)[^{]*\{',
);

/// The annotations that lead [raw], before any signature text.
String _leadingAnnotations(String raw) =>
    RegExp(r'^(?:@\w+(?:\([^)]*\))?\s*)*').firstMatch(raw.trim())!.group(0)!;

bool _isExportAnnotation(String text) =>
    RegExp(r'@JSExport\s*\(').hasMatch(text);

/// The names of the classes in [source] that carry a class-level
/// `@JSExport()`: a class-level annotation exposes every concrete instance
/// member, private ones included, which is not what the bridge wants.
List<String> _classLevelExports(String source) {
  final code = _stripped(source);
  return [
    for (final c in _classPattern.allMatches(code))
      if (_isExportAnnotation(c.group(1)!)) c.group(2)!
  ];
}

/// The members of every class in [source] that carry member-level
/// `@JSExport()`, as `Class.member` signatures:
/// `(name, returnType, parameterTypes)`.
List<({String owner, String name, String returns, List<String> params})>
    _exportedMembers(String source) {
  final code = _stripped(source);
  final members =
      <({String owner, String name, String returns, List<String> params})>[];
  for (final c in _classPattern.allMatches(code)) {
    final owner = c.group(2)!;
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
  // Bind the annotation to the member: only a member-level `@JSExport()`
  // exports it, detected before the leading annotations are stripped.
  if (!_isExportAnnotation(_leadingAnnotations(raw))) return null;
  var text = _signature(raw);
  if (text.isEmpty) return null;
  // Drop leading annotations like `@override` or `@JSExport()`.
  text = text.replaceFirst(RegExp(r'^(?:@\w+(?:\([^)]*\))?\s+)+'), '');
  // A static member is not part of the instance's JS surface.
  if (RegExp(r'^static\s+').hasMatch(text)) return null;
  // Drop member modifiers that are not types.
  text = text.replaceFirst(RegExp(r'^(?:external|late)\s+'), '');
  if (text.startsWith('$owner(') ||
      text.startsWith('$owner.') ||
      text.startsWith('factory ')) {
    return null;
  }
  final method = RegExp(r'^(?:(.+?)\s+)?(\w+)\s*\((.*)\)$').firstMatch(text);
  if (method != null) {
    final prefix = method.group(1)?.trim();
    final name = method.group(2)!;
    if (name == owner) return null;
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
    return (
      owner: owner,
      name: getter.group(2)!,
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
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };

  test('every member carrying @JSExport takes and returns JS types only', () {
    final exported = {for (final s in sources.values) ..._exportedMembers(s)};
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

  test('the check flags a class-level @JSExport', () {
    const bad = '''
@JSExport()
class Leaky {
  JSPromise<JSAny?> fine() => throw 0;
}
''';
    expect(_classLevelExports(bad), ['Leaky']);
  });

  test('no class carries a class-level @JSExport', () {
    for (final MapEntry(:key, :value) in sources.entries) {
      expect(_classLevelExports(value), isEmpty, reason: key);
    }
  });

  test('member-level @JSExport appears only in lib/src/js/bridge.dart', () {
    expect(
        sources.entries
            .where((e) => _exportedMembers(e.value).isNotEmpty)
            .map((e) => e.key),
        ['lib/src/js/bridge.dart']);
  });
}
