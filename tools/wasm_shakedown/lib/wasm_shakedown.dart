/// Walks a Dart package's import/export graph and reports every file naming a
/// platform library that cannot work on the target platform.
///
/// **Why this exists.** `dart compile wasm` does *not* reject `dart:io`: it
/// ships a stub whose members throw `UnsupportedError` when called, so a
/// browser-hostile import compiles clean and fails at runtime instead. Measured
/// on Dart 3.12. A compile gate therefore cannot police a web-safe barrel — only
/// `dart:ffi` is rejected outright. This walk is what holds the line; the
/// compile gate catches the complementary `dart:ffi` case.
///
/// Resolution follows the *target* platform's view of configurable URIs, so
/// `import 'a_stub.dart' if (dart.library.io) 'a_io.dart';` is followed down the
/// branch that platform would actually take — see [webEnvironment] and
/// [ioEnvironment].
///
/// Typical use from a package's `test/wasm/dep_tree_test.dart`:
///
/// ```dart
/// final result = shakedown('package:at_utils/at_logger.dart');
/// expect(result.blockedPackages, isEmpty, reason: result.report());
/// ```
library;

import 'dart:convert';
import 'dart:io';

/// Platform libraries with no working implementation in a browser.
const defaultForbidden = {
  'dart:io',
  'dart:ffi',
  'dart:isolate',
  'dart:mirrors',
  'dart:html',
  'dart:js',
  'dart:js_util',
};

/// How `if (dart.library.x)` evaluates in a dart2wasm build.
///
/// Verified against Dart 3.12 by compiling a probe and reading the values back
/// at runtime, rather than assumed.
const webEnvironment = {
  'dart.library.io': false,
  'dart.library.ffi': false,
  'dart.library.html': false,
  'dart.library.js': false,
  'dart.library.js_interop': true,
  'dart.library.js_util': true,
};

/// How `if (dart.library.x)` evaluates on the VM.
///
/// Use this to assert the *other* half of a conditional seam — that a barrel
/// documented as native-only really does carry the platform code it claims,
/// rather than having quietly collapsed into its own stub.
const ioEnvironment = {
  'dart.library.io': true,
  'dart.library.ffi': true,
  'dart.library.html': false,
  'dart.library.js': false,
  'dart.library.js_interop': false,
  'dart.library.js_util': false,
};

/// The result of a [shakedown] walk.
class Shakedown {
  /// Absolute file path -> the forbidden libraries it imports, sorted.
  final Map<String, List<String>> offenders;

  /// Package name -> absolute `lib/` path, as resolved from the package config.
  final Map<String, String> packageRoots;

  /// How many files the walk visited. A guard against a path bug silently
  /// stopping the traversal at the entry point.
  final int filesWalked;

  /// Files that were imported but do not exist on disk.
  final List<String> missingFiles;

  Shakedown(
      this.offenders, this.packageRoots, this.filesWalked, this.missingFiles);

  /// The packages owning at least one offending file.
  Set<String> get blockedPackages =>
      offenders.keys.map(packageOf).whereType<String>().toSet();

  /// The package owning [path], by longest matching root.
  String? packageOf(String path) {
    String? best;
    for (final entry in packageRoots.entries) {
      if (path.startsWith(entry.value) &&
          (best == null || entry.value.length > packageRoots[best]!.length)) {
        best = entry.key;
      }
    }
    return best;
  }

  /// Offenders owned by [package], keyed by path relative to the package root
  /// (e.g. `lib/src/foo.dart`) so failure messages are readable.
  Map<String, List<String>> offendersIn(String package) {
    final root = packageRoots[package];
    if (root == null) return const {};
    return {
      for (final entry in offenders.entries)
        if (packageOf(entry.key) == package)
          'lib/${entry.key.substring(root.length)}': entry.value,
    };
  }

  /// A human-readable listing for use as a test failure `reason`.
  String report() => (offenders.keys.toList()..sort())
      .map((k) => '  ${packageOf(k)}: $k -> ${offenders[k]!.join(', ')}')
      .join('\n');
}

/// Walks the import/export graph from [entryUri], following [environment]'s
/// view of configurable URIs.
///
/// [entryUri] may be a `package:` URI or a file path. Traversal crosses package
/// boundaries via the workspace's `.dart_tool/package_config.json`, found by
/// walking up from [from] (defaults to the current directory), so third-party
/// dependencies are covered too.
Shakedown shakedown(
  String entryUri, {
  Map<String, bool> environment = webEnvironment,
  Set<String> forbidden = defaultForbidden,
  Directory? from,
}) {
  final roots = resolvePackageRoots(from: from);
  final entry = _resolve(entryUri, '.', roots);
  if (entry == null) {
    throw ArgumentError.value(entryUri, 'entryUri', 'could not be resolved');
  }

  final offenders = <String, List<String>>{};
  final missing = <String>[];
  final seen = <String>{};
  final queue = <String>[entry];

  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) {
      missing.add(path);
      continue;
    }
    for (final match in _directive.allMatches(file.readAsStringSync())) {
      final target = selectUri(match.group(1)!, environment);
      if (forbidden.contains(target)) {
        offenders.putIfAbsent(path, () => []).add(target);
        continue;
      }
      final resolved = _resolve(target, file.parent.path, roots);
      if (resolved != null) queue.add(resolved);
    }
  }
  for (final list in offenders.values) {
    list.sort();
  }
  return Shakedown(offenders, roots, seen.length, missing);
}

/// The URI [clause] resolves to under [environment]: the first `if (...)`
/// branch whose condition holds, else the default (first) URI.
String selectUri(String clause, Map<String, bool> environment) {
  for (final match in _conditional.allMatches(clause)) {
    if (environment[match.group(1)] == true) return match.group(2)!;
  }
  return _firstUri.firstMatch(clause)!.group(1)!;
}

/// Package name -> absolute `lib/` path, from the nearest package config.
///
/// Walks up from [from] (default: the current directory) so this works whether
/// a test runs from its package directory or the workspace root.
Map<String, String> resolvePackageRoots({Directory? from}) {
  var dir = from ?? Directory.current;
  File? config;
  while (true) {
    final candidate = File('${dir.path}/.dart_tool/package_config.json');
    if (candidate.existsSync()) {
      config = candidate;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  if (config == null) {
    throw StateError('no .dart_tool/package_config.json found above '
        '${(from ?? Directory.current).path} — run `dart pub get` first');
  }

  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final base = Uri.file('${config.parent.path}/');
  return {
    for (final package in json['packages'] as List)
      (package as Map)['name'] as String: base
          .resolve('${package['rootUri']}/')
          .resolve((package['packageUri'] as String?) ?? 'lib/')
          .toFilePath(),
  };
}

/// An `import`/`export` with its optional `if (...)` alternatives.
final _directive = RegExp(
  r'''^\s*(?:import|export)\s+(['"][^'"]+['"](?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
  multiLine: true,
);
final _firstUri = RegExp(r'''['"]([^'"]+)['"]''');
final _conditional = RegExp(r'''if\s*\(\s*([\w.]+)\s*\)\s*['"]([^'"]+)['"]''');

/// `package:` and relative URIs to absolute paths. `dart:` URIs and unknown
/// packages return null — the caller either flags them or skips them.
String? _resolve(String uri, String fromDir, Map<String, String> roots) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final root = roots[rest.substring(0, slash)];
    return root == null ? null : '$root${rest.substring(slash + 1)}';
  }
  return Uri.file('$fromDir/').resolve(uri).toFilePath();
}
