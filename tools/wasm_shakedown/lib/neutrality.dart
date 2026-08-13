/// The source-level neutrality gates: no platform conditionals, and no throwing
/// platform fallbacks.
///
/// These are line scans over a package's `lib/` tree rather than graph walks,
/// because what they forbid is a *way of writing code* rather than a reachable
/// import. The walk in `wasm_shakedown.dart` answers "can a browser reach
/// `dart:io` from this barrel"; these answer "has someone papered over a
/// platform difference inside a package that is supposed to have none".
///
/// Both scans read a package's location from the workspace package config via
/// [resolvePackageRoots], so they work from any directory in the workspace.
///
/// Typical use from `test/neutrality_test.dart`:
///
/// ```dart
/// final hits = conditionalImports();
/// expect(hits, isEmpty, reason: describe(hits));
/// ```
library;

import 'dart:io';

import 'wasm_shakedown.dart' show resolvePackageRoots;

/// The packages governed by the no-conditionals and no-throwing-stub rules.
///
/// `at_auth` is deliberately absent: the post-quantum program owns that package,
/// and a gate here would fail on work this project does not control.
const neutralPackages = <String>[
  'at_client',
  'at_lookup',
  'at_utils',
  'at_chops',
  'at_server_status',
];

/// A platform conditional: `import 'a.dart' if (dart.library.io) 'b.dart';`.
///
/// Tolerates whitespace the literal form does not, so `if ( dart.library.io )`
/// cannot slip past.
final conditionalPattern = RegExp(r'if\s*\(\s*dart\.library\.');

/// A thrown platform-capability refusal.
///
/// Deliberately narrow — `throw UnsupportedError`, the exact construct the
/// no-throwing-stubs rule names. It does not chase `Future.error(...)`,
/// `Error.throwWithStackTrace`, or a refusal raised through a helper. Widening
/// it is a judgement call to make when a real evasion shows up, not
/// speculatively: every broadening costs allow-list entries, and an allow-list
/// long enough to skim past is a gate that has stopped working.
final throwingStubPattern = RegExp(r'throw\s+UnsupportedError');

/// One matching line.
class SourceHit {
  /// Path relative to the owning package, e.g. `lib/src/foo.dart`.
  final String path;

  /// The package that owns [path].
  final String package;

  /// 1-indexed line number.
  final int line;

  /// The matching line, trimmed.
  final String text;

  const SourceHit(this.package, this.path, this.line, this.text);

  @override
  String toString() => '$package/$path:$line  $text';
}

/// A source location a gate deliberately permits.
///
/// The reason is positional rather than optional because an allow-list entry
/// without one is indistinguishable from an oversight six months later. A
/// read-only keystore subtype refusing `write` is a legitimate entry; a core
/// storage path refusing to store is the defect the gate exists to catch, and
/// the difference between the two lives only in the reason.
class Excused {
  /// Package-relative path, matched exactly against [SourceHit.path].
  final String path;

  /// The package that owns [path].
  final String package;

  /// Why this location is permitted.
  final String reason;

  const Excused(this.package, this.path, this.reason);
}

/// Every conditional-import site in [packages].
///
/// A conditional import is a compile-time answer to a runtime question: it keeps
/// platform knowledge inside the layer that is meant to be neutral, and its
/// non-native branch is a stub — the reachable-and-explosive failure this
/// project exists to remove.
List<SourceHit> conditionalImports({
  Iterable<String> packages = neutralPackages,
  Directory? from,
}) =>
    scan(conditionalPattern, packages: packages, from: from);

/// Every `throw UnsupportedError` site in [packages].
///
/// A capability a platform lacks must be unreachable there, not
/// reachable-and-explosive. A throwing stub converts a build error into a
/// production error and moves the discovery point from CI to a user.
List<SourceHit> throwingStubs({
  Iterable<String> packages = neutralPackages,
  Directory? from,
}) =>
    scan(throwingStubPattern, packages: packages, from: from);

/// [hits] minus the ones [allowList] excuses, by (package, path).
///
/// Excusing a whole file rather than a line is deliberate: a line number in an
/// allow-list goes stale on the next unrelated edit above it, and a stale
/// allow-list silently starts excusing something else.
List<SourceHit> unexcused(
        List<SourceHit> hits, Iterable<Excused> allowList) =>
    hits
        .where((hit) => !allowList
            .any((e) => e.package == hit.package && e.path == hit.path))
        .toList();

/// [hits] as a multi-line listing for a test failure `reason`.
String describe(Iterable<SourceHit> hits) =>
    hits.map((hit) => '  $hit').join('\n');

/// Every line in [packages]' `lib/` trees matching [pattern], comments stripped.
///
/// Public so a test can point it at a pattern that is *known* to be present and
/// confirm the scan reaches real files. Both gates below assert an absence, and
/// an absence is exactly what a scan that silently found nothing also reports.
List<SourceHit> scan(
  RegExp pattern, {
  Iterable<String> packages = neutralPackages,
  Directory? from,
}) {
  final roots = resolvePackageRoots(from: from);
  final hits = <SourceHit>[];
  for (final package in packages) {
    final root = roots[package];
    if (root == null) {
      throw StateError('$package is not in the workspace package config — '
          'either it was renamed, or `dart pub get` has not run');
    }
    final dir = Directory(root);
    if (!dir.existsSync()) {
      throw StateError('$package resolves to $root, which does not exist');
    }
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!pattern.hasMatch(withoutLineComment(lines[i]))) continue;
        hits.add(SourceHit(
          package,
          'lib/${file.path.substring(root.length)}',
          i + 1,
          lines[i].trim(),
        ));
      }
    }
  }
  return hits;
}

/// [line] with any `//` comment removed.
///
/// This, rather than the patterns, is what keeps prose about conditional imports
/// and throwing stubs — of which the neutral packages will accumulate plenty as
/// the port proceeds — from reading as a violation. A real directive or `throw`
/// can never live inside a line comment, so nothing is lost. Block comments are
/// not handled; a `/* ... */` spanning a violation-shaped line would trip the
/// gate, which is the safe direction to be wrong in.
String withoutLineComment(String line) {
  final index = line.indexOf('//');
  return index < 0 ? line : line.substring(0, index);
}
