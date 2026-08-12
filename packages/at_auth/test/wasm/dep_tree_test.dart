import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Dependency-tree shakedown for `package:at_auth/at_auth_web.dart`.
///
/// Walks every `import`/`export` reachable from the web barrel — across package
/// boundaries, into at_chops, at_lookup, at_utils and third-party packages — and
/// reports every file that names a platform library a browser cannot provide.
///
/// **Why a test and not a compile.** `dart compile wasm` does not reject
/// `dart:io`: it ships a stub whose members throw `UnsupportedError` when
/// called, so a browser-hostile import compiles clean and fails at runtime
/// instead. Measured on Dart 3.12. That makes this walk the only thing standing
/// between the barrel split and its silent decay — `test/wasm/smoke.dart` +
/// `dart compile wasm` catches the complementary case, a `dart:ffi` import,
/// which the compiler *does* reject.
///
/// The walk resolves configurable URIs the way a **web** build does
/// (`dart.library.io` false, `dart.library.js_interop` true), so a
/// `defaults_stub.dart if (dart.library.io) defaults_io.dart` pair is followed
/// down its stub branch — exactly what dart2wasm would do.
void main() {
  group('at_auth_web.dart dependency tree', () {
    late _Shakedown result;

    setUpAll(() => result = _walk('package:at_auth/at_auth_web.dart'));

    test('no at_auth-owned file names a browser-hostile library', () {
      final owned = result.offendersIn('at_auth');
      expect(
        owned,
        isEmpty,
        reason: 'These at_auth sources are reachable from at_auth_web.dart but '
            'name a platform library WASM cannot provide. Either move them '
            'behind at_auth.dart (the dart:io barrel), or — the usual cause — '
            'stop importing the public `package:at_auth/at_auth.dart` barrel '
            'from inside lib/src/ and import the narrow src path instead:\n'
            '${owned.entries.map((e) => '  ${e.key} -> ${e.value.join(', ')}').join('\n')}',
      );
    });

    test('the set of externally-blocked packages has not grown', () {
      // Measured 2026-08-12. This list is a ratchet in BOTH directions: a new
      // entry means someone introduced a dependency that cannot run in a
      // browser, and a missing entry means a blocker was fixed and this
      // expectation should shrink. Either way, read the failure and update it
      // deliberately.
      const expected = {
        // at_lookup's socket transport — the T-series in
        // docs/projects/wasm/plan.md. The largest remaining blocker.
        'at_lookup',
        // at_utils: src/logging/handlers.dart (FileLoggingHandler, stderr),
        // src/config/app_config.dart (File) and
        // src/networking/pseudo_server_socket.dart (ServerSocket). Tasks I1-I3.
        'at_utils',
        // at_server_status: src/model/at_status.dart uses HttpStatus purely for
        // five int constants. Task I13 — the cheapest item on the list.
        'at_server_status',
        // Third-party: chalkdart reads the terminal for ANSI support. Reached
        // via at_utils' progress.dart (at_progress.dart) and handlers.dart, so
        // it survives even a perfect at_utils logging split. Needs an upstream
        // fix, a conditional seam in at_utils, or dropping the dependency.
        'chalkdart',
      };

      expect(result.blockedPackages, expected,
          reason: 'Externally-blocked packages changed.\n'
              'Offending files:\n${result.report()}');
    });

    test('the walk actually traversed the tree', () {
      // Guards against the whole suite passing because a path bug made the
      // traversal stop at the entry point.
      expect(result.filesWalked, greaterThan(100));
      expect(result.missingFiles, isEmpty,
          reason: 'imported but not found: ${result.missingFiles}');
    });
  });

  test('at_auth.dart, the default barrel, does reach dart:io', () {
    // The other half of the invariant: if this ever comes up empty the split has
    // collapsed into one barrel and the test above became vacuous.
    final full = _walk('package:at_auth/at_auth.dart').offendersIn('at_auth');
    expect(full.keys, contains('lib/src/keys/io/file_io.dart'));
    expect(full.keys, contains('lib/src/io/probe.dart'));
  });
}

/// Platform libraries with no working implementation in a browser.
const _forbidden = {
  'dart:io',
  'dart:ffi',
  'dart:isolate',
  'dart:mirrors',
  'dart:html',
  'dart:js',
  'dart:js_util',
};

/// How `if (dart.library.x)` evaluates in a dart2wasm build. Verified against
/// Dart 3.12 by compiling a probe and reading the values back at runtime.
const _webEnv = {
  'dart.library.io': false,
  'dart.library.ffi': false,
  'dart.library.html': false,
  'dart.library.js': false,
  'dart.library.js_interop': true,
  'dart.library.js_util': true,
};

/// An `import`/`export` with its optional `if (...)` alternatives.
final _directive = RegExp(
  r'''^\s*(?:import|export)\s+(['"][^'"]+['"](?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
  multiLine: true,
);
final _firstUri = RegExp(r'''['"]([^'"]+)['"]''');
final _conditional = RegExp(r'''if\s*\(\s*([\w.]+)\s*\)\s*['"]([^'"]+)['"]''');

class _Shakedown {
  final Map<String, List<String>> offenders; // absolute path -> libraries
  final Map<String, String> packageRoots; // package name -> lib/ path
  final int filesWalked;
  final List<String> missingFiles;

  _Shakedown(
      this.offenders, this.packageRoots, this.filesWalked, this.missingFiles);

  String? _packageOf(String path) {
    String? best;
    for (final e in packageRoots.entries) {
      if (path.startsWith(e.value) &&
          (best == null || e.value.length > packageRoots[best]!.length)) {
        best = e.key;
      }
    }
    return best;
  }

  Set<String> get blockedPackages =>
      offenders.keys.map(_packageOf).whereType<String>().toSet();

  /// Offenders owned by [package], keyed by path relative to the package root.
  Map<String, List<String>> offendersIn(String package) {
    final root = packageRoots[package]!;
    return {
      for (final e in offenders.entries)
        if (_packageOf(e.key) == package)
          'lib/${e.key.substring(root.length)}': e.value,
    };
  }

  String report() => (offenders.keys.toList()..sort())
      .map((k) => '  ${_packageOf(k)}: $k -> ${offenders[k]!.join(', ')}')
      .join('\n');
}

_Shakedown _walk(String entry) {
  final roots = _resolvePackageRoots();
  final offenders = <String, List<String>>{};
  final missing = <String>[];
  final seen = <String>{};
  final queue = <String>[_resolve(entry, '.', roots)!];

  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) {
      missing.add(path);
      continue;
    }
    for (final match in _directive.allMatches(file.readAsStringSync())) {
      final target = _selectUri(match.group(1)!);
      if (_forbidden.contains(target)) {
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
  return _Shakedown(offenders, roots, seen.length, missing);
}

/// The URI a web build resolves [clause] to: the first `if (...)` branch whose
/// condition holds under [_webEnv], else the default (first) URI.
String _selectUri(String clause) {
  for (final m in _conditional.allMatches(clause)) {
    if (_webEnv[m.group(1)] == true) return m.group(2)!;
  }
  return _firstUri.firstMatch(clause)!.group(1)!;
}

/// `package:` and relative URIs to absolute paths. `dart:` and unknown packages
/// return null — the caller either flags them or skips them.
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

/// Package name -> absolute `lib/` path, from the workspace package config.
///
/// Walks up from the CWD so the test works whether it is run from the package
/// directory or the workspace root.
Map<String, String> _resolvePackageRoots() {
  var dir = Directory.current;
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
    fail('no .dart_tool/package_config.json found — run `dart pub get` first');
  }

  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final base = Uri.file('${config.parent.path}/');
  return {
    for (final p in json['packages'] as List)
      (p as Map)['name'] as String: base
          .resolve('${p['rootUri']}/')
          .resolve((p['packageUri'] as String?) ?? 'lib/')
          .toFilePath(),
  };
}
