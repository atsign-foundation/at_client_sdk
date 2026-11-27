// The `@JSExport` scanner shared by the two tests that read the bridge
// surface: `export_boundary_test.dart` checks the types an exported member
// takes and returns, and `manifest_test.dart` pins the names it exports.
// Both read the same sources, so they read them with one parser.

/// An exported member: the class [owner] and the JS name [name], with the
/// Dart signature the member exports.
typedef ExportedMember = ({
  String owner,
  String name,
  String returns,
  List<String> params,
});

const _jsExport = r'@JSExport\s*\(';

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
    // A `@JSExport('name')` argument is a string literal, but its text is what
    // the member exports, so the annotation is copied whole rather than having
    // its literal replaced.
    if (source.startsWith('@JSExport(', i)) {
      var j = i + '@JSExport('.length;
      var quote = '';
      while (j < n) {
        final ch = source[j];
        if (quote.isEmpty) {
          if (ch == '\'' || ch == '"') {
            quote = ch;
          } else if (ch == ')') {
            j++;
            break;
          }
        } else if (ch == quote) {
          quote = '';
        }
        j++;
      }
      out.write(source.substring(i, j));
      i = j;
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

bool _isExportAnnotation(String text) => RegExp(_jsExport).hasMatch(text);

/// The name a `@JSExport('name')` or `@JSExport("name")` declares, or null
/// when the annotation is bare and the member keeps its own name.
String? _exportName(String annotations) {
  final quoted = RegExp(
    r'''@JSExport\(\s*(?:'([^']*)'|"([^"]*)")\s*\)''',
  ).firstMatch(annotations);
  return quoted?.group(1) ?? quoted?.group(2);
}

/// The names of the classes in [source] that carry a class-level
/// `@JSExport()`: a class-level annotation exposes every concrete instance
/// member, private ones included, which is not what the bridge wants.
List<String> classLevelExports(String source) {
  final code = _stripped(source);
  return [
    for (final c in _classPattern.allMatches(code))
      if (_isExportAnnotation(c.group(1)!)) c.group(2)!
  ];
}

/// The members of every class in [source] that carry member-level
/// `@JSExport()`, with the name they export: a `@JSExport('name')` renames the
/// member, while a bare `@JSExport()` keeps its own.
List<ExportedMember> exportedMembers(String source) {
  final code = _stripped(source);
  final members = <ExportedMember>[];
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

/// `{class: exported names}` for each class in [source] with exported
/// members, each list sorted.
Map<String, List<String>> exportedSurface(String source) {
  final surface = <String, List<String>>{};
  for (final m in exportedMembers(source)) {
    (surface[m.owner] ??= <String>[]).add(m.name);
  }
  return {
    for (final MapEntry(:key, :value) in surface.entries) key: value..sort()
  };
}

ExportedMember? _parseMember(String owner, String raw) {
  // Bind the annotation to the member: only a member-level `@JSExport()`
  // exports it, detected before the leading annotations are stripped.
  final annotations = _leadingAnnotations(raw);
  if (!_isExportAnnotation(annotations)) return null;
  final declared = _exportName(annotations);
  var text = _signature(raw);
  if (text.isEmpty) {
    throw StateError('@JSExport on $owner is not on a member');
  }
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
        name: declared ?? name,
        returns: 'void',
        params: _parameterTypes(method.group(3)!),
      );
    }
    return (
      owner: owner,
      name: declared ?? name,
      returns: prefix ?? 'dynamic',
      params: _parameterTypes(method.group(3)!),
    );
  }
  final getter = RegExp(r'^(?:(.+?)\s+)?get\s+(\w+)$').firstMatch(text);
  if (getter != null) {
    return (
      owner: owner,
      name: declared ?? getter.group(2)!,
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
    if (qualifier == null && type == null) {
      throw StateError(
          '@JSExport on $owner.$name is not on a method, getter, setter or '
          'field');
    }
    return (
      owner: owner,
      name: declared ?? name,
      returns: type ?? 'dynamic',
      params: const [],
    );
  }
  throw StateError(
      '@JSExport on $owner is not on a method, getter, setter or field');
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
      for (final raw in splitTopLevel(list.replaceAll(RegExp(r'[\[\]{}]'), '')))
        if (raw.trim().isNotEmpty)
          raw
              .trim()
              .replaceFirst(RegExp(r'^required\s+'), '')
              .replaceFirst(RegExp(r'\s*=.*$'), '')
              .trim()
              .replaceFirst(RegExp(r'\s*\w+$'), '')
              .trim()
    ];

/// [text] split at its depth-0 commas, ignoring commas inside `<>`.
List<String> splitTopLevel(String text) {
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

/// The option names `BridgeEntry._options` reads, split the way the method
/// branches: [common] is everything before the `if (_flag(object, 'passkey'))`
/// block, its own `'passkey'` test included; [passkey] is inside that block;
/// [keys] is after it.
({Set<String> common, Set<String> keys, Set<String> passkey}) createOptionNames(
    String source) {
  final body = _bodyOf(source, 'SessionOptions _options(');
  final branch = RegExp(
    r"if\s*\(\s*_flag\(object,\s*'passkey'\)\s*\)\s*\{",
  ).firstMatch(body);
  if (branch == null) {
    throw StateError("bridge.dart has no `if (_flag(object, 'passkey'))`");
  }
  final close = _matchingBrace(body, branch.end - 1);
  return (
    common: _optionNames(body.substring(0, branch.end)),
    passkey: _optionNames(body.substring(branch.end, close)),
    keys: _optionNames(body.substring(close + 1)),
  );
}

/// The names in `_own(object, '…')`, `_field(object, '…')` and
/// `_flag(object, '…')` calls in [text].
Set<String> _optionNames(String text) => {
      for (final match in RegExp(r"_(?:own|field|flag)\(object,\s*'([^']+)'\)")
          .allMatches(text))
        match.group(1)!,
    };

/// The keys of the one `_envelope({…})` map inside
/// `BridgeSession.subscribe`'s body, sorted.
List<String> subscribeEnvelopeFields(String source) {
  final body = _bodyOf(source, 'JSAny subscribe(');
  final call = body.indexOf('_envelope({');
  if (call < 0 || body.indexOf('_envelope(', call + 1) >= 0) {
    throw StateError('subscribe has no single _envelope({…})');
  }
  final open = call + '_envelope('.length;
  final close = _matchingBrace(body, open);
  final fields = {
    for (final match
        in RegExp(r"'([^']+)'\s*:").allMatches(body.substring(open, close)))
      match.group(1)!,
  };
  return fields.toList()..sort();
}

/// The status strings `AtClientSession` can report: every string literal in
/// `_statusOf`, plus the `?? '…'` fallback the constructor starts with, sorted.
List<String> statusNames(String source) {
  final statusOf = _bodyOf(source, 'String? _statusOf(');
  final constructor = _bodyOf(source, 'AtClientSession(this._client');
  final names = {
    for (final match in RegExp(r"'([^']*)'").allMatches(statusOf))
      match.group(1)!,
    for (final match in RegExp(r"\?\?\s*'([^']*)'").allMatches(constructor))
      match.group(1)!,
  };
  return names.toList()..sort();
}

/// The body of the declaration that starts at the first occurrence of
/// [signature] in [source]: the text between its body's braces. The parameter
/// list's `)` is found first, so a named parameter group's `{` is not mistaken
/// for the body.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) throw StateError('no `$signature` in the source');
  final closeParen = _matchingBrace(source, source.indexOf('(', start));
  final openBrace = source.indexOf('{', closeParen);
  final closeBrace = _matchingBrace(source, openBrace);
  return source.substring(openBrace + 1, closeBrace);
}

/// The index of the bracket that closes the one at [open] in [source], with
/// comments and string literals skipped so a bracket inside either cannot
/// change the depth.
int _matchingBrace(String source, int open) {
  final opener = source[open];
  final String closer;
  if (opener == '{') {
    closer = '}';
  } else if (opener == '(') {
    closer = ')';
  } else if (opener == '[') {
    closer = ']';
  } else {
    throw StateError('${source.substring(open)} does not start a bracket');
  }
  var depth = 0;
  var i = open;
  while (i < source.length) {
    final ch = source[i];
    if (ch == '/' && i + 1 < source.length && source[i + 1] == '/') {
      i += 2;
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (ch == '/' && i + 1 < source.length && source[i + 1] == '*') {
      var nesting = 1;
      i += 2;
      while (i < source.length && nesting > 0) {
        if (source[i] == '/' && i + 1 < source.length && source[i + 1] == '*') {
          nesting++;
          i += 2;
        } else if (source[i] == '*' &&
            i + 1 < source.length &&
            source[i + 1] == '/') {
          nesting--;
          i += 2;
        } else {
          i++;
        }
      }
      continue;
    }
    if (ch == '\'' || ch == '"') {
      final triple =
          i + 2 < source.length && source[i + 1] == ch && source[i + 2] == ch;
      final delim = triple ? ch * 3 : ch;
      i += delim.length;
      while (i < source.length && !source.startsWith(delim, i)) {
        if (!triple && source[i] == '\n') break;
        if (source[i] == r'\' && i + 1 < source.length) {
          i += 2;
          continue;
        }
        i++;
      }
      if (source.startsWith(delim, i)) i += delim.length;
      continue;
    }
    if (ch == opener) depth++;
    if (ch == closer) {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  throw StateError('unbalanced $opener in the source');
}
