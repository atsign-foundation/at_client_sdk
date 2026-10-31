import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The largest `core.js` a build may write.
const int coreBudget = 300 * 1024;

/// The largest flow file a build may write.
const int flowBudget = 1536 * 1024;

/// Size budgets, which a test may lower.
class Budgets {
  /// Creates budgets.
  const Budgets({this.core = coreBudget, this.flow = flowBudget});

  /// The cap on `core.js`.
  final int core;

  /// The cap on each flow file.
  final int flow;
}

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k as String).toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return [for (final x in v) _sorted(x)];
  return v;
}

/// [value] as JSON with sorted keys, and with every character that could
/// end a script or start markup escaped.
String canonicalJson(Object? value) {
  final s = const JsonEncoder.withIndent(' ').convert(_sorted(value));
  final out = StringBuffer();
  for (final c in s.runes) {
    if (c == 0x3C || c == 0x3E || c == 0x26 || c == 0x2028 || c == 0x2029) {
      out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// A classic script that sets `window.<global>[key]`, or `window.<global>`
/// when [key] is null.
String classicScript(String global, String? key, Object? value) {
  final json = canonicalJson(value);
  if (key == null) return 'window.$global = $json;\n';
  return 'window.$global = window.$global || {};\n'
      'window.$global[${canonicalJson(key)}] = $json;\n';
}

/// Whether [href] may appear on the page: a path inside this repository,
/// or a page under https://github.com/atsign-foundation/.
bool allowedHref(String href, {required bool Function(String) existsInRepo}) {
  if (href.startsWith('https://github.com/atsign-foundation/')) {
    final rest = href.substring('https://github.com/'.length);
    return !rest.contains('..') &&
        !rest.contains('//') &&
        RegExp(r'''^[A-Za-z0-9_./#%:@+=~-]+$''').hasMatch(rest);
  }
  if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_./-]*(#L\d+(-L\d+)?)?$')
      .hasMatch(href)) {
    return false;
  }
  final path = href.split('#').first;
  if (p.split(path).contains('..')) return false;
  return existsInRepo(path);
}

/// Writes [files] under [dir] so an interrupted write leaves every old file
/// whole: each is written to a staging directory beside it and renamed
/// into place, and [stale] files are removed last.
void writeAtomically(String dir, Map<String, String> files,
    {List<String> stale = const []}) {
  final stage = Directory(p.join(dir, '.staging-$pid'));
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  stage.createSync(recursive: true);
  try {
    for (final e in files.entries) {
      final f = File(p.join(stage.path, e.key));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(e.value, flush: true);
    }
    for (final e in files.entries) {
      final target = File(p.join(dir, e.key));
      target.parent.createSync(recursive: true);
      File(p.join(stage.path, e.key)).renameSync(target.path);
    }
    for (final s in stale) {
      final f = File(p.join(dir, s));
      if (f.existsSync()) f.deleteSync();
    }
  } finally {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
}
