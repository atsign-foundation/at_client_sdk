// These gates read the filesystem to inspect sources, so they run on the VM
// only. Without this they would be compiled and launched by the T2
// node+dart2wasm platform run, where dart:io throws and the failure looks like a
// neutrality problem rather than a test that was never meant to run there.
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:wasm_shakedown/neutrality.dart';

/// The two source-level neutrality gates, over every package the
/// no-conditionals and no-throwing-stub rules govern.
///
/// Both assert an absence, so both are one bug away from being vacuously green —
/// hence the scanner-reaches-real-files test at the bottom. Read that one before
/// trusting the two above it.
///
/// The complementary gate is the per-package `test/wasm/dep_tree_test.dart`,
/// which walks the reachable import graph. Neither subsumes the other: the walk
/// cannot see a conditional's unreachable branch or a `throw` in a file it
/// legitimately reaches, and these scans cannot see anything a dependency does.
void main() {
  group('no platform conditionals (T0.3)', () {
    // EMPTY, and the intent is that it stays empty. A conditional import is a
    // compile-time answer to a runtime question: it leaves platform knowledge
    // inside the layer that is supposed to be neutral, makes the core's
    // dependency graph platform-dependent, and its non-native branch is a stub —
    // which is the reachable-and-explosive failure this project exists to
    // remove. Platform behaviour is injected from outside instead.
    //
    // If you are here because you added one for backwards compatibility: that
    // is the case the rule was written against, and the answer is a platform
    // implementer package, not a branch.
    const allowList = <Excused>[];

    test('no neutral package names dart.library in a conditional', () {
      final hits = unexcused(conditionalImports(), allowList);
      expect(hits, isEmpty,
          reason: 'Platform conditionals in packages that must not know '
              'platforms differ:\n${describe(hits)}');
    });
  });

  group('no throwing platform fallbacks (T0.4)', () {
    // EMPTY today. Unlike the conditionals list above, this one has a
    // legitimate shape: a read-only subtype refusing `write` is a genuine
    // "this operation does not exist here", not a platform capability papered
    // over. What is never acceptable is a core code path that a platform can
    // reach and that throws when it gets there.
    //
    // The reason field is what separates the two. Write it for a reader who
    // does not have the surrounding conversation.
    const allowList = <Excused>[];

    test('no neutral package throws UnsupportedError', () {
      final hits = unexcused(throwingStubs(), allowList);
      expect(hits, isEmpty,
          reason: 'Throwing platform fallbacks — a capability a platform lacks '
              'must be unreachable there, not reachable-and-explosive:\n'
              '${describe(hits)}');
    });

    test('UnimplementedError is deliberately out of scope', () {
      // Not a gap — a decision, recorded here because the next person to read
      // the gate will wonder. `UnimplementedError` marks not-yet-implemented or
      // deprecated API, of which these packages hold a handful of legitimate
      // uses (at_client's at_rpc.dart and the deprecated AtClient.startMonitor,
      // at_chops' at_chops_impl.dart, the collections query builders). Gating on
      // it would mean excusing all of them, and an allow-list long enough to
      // skim past is a gate that has stopped working.
      //
      // This test pins the count so the reasoning cannot quietly go stale: if
      // these grow a lot, revisit whether the pattern should widen after all.
      final hits = scan(RegExp(r'throw\s+UnimplementedError'));
      expect(hits, hasLength(lessThanOrEqualTo(8)),
          reason: 'UnimplementedError use has grown past what the exclusion '
              'above reasoned about — re-read that comment and decide '
              'deliberately:\n${describe(hits)}');
    });
  });

  test('the scanner reaches real files', () {
    // The guard that keeps the two gates from being vacuous. `scan` throws if a
    // package is missing from the workspace config or its lib/ is absent, so the
    // remaining failure mode is a traversal that finds files but reads nothing
    // useful from them. Every package here has hundreds of import directives.
    final imports = scan(RegExp(r'^\s*import\s'));
    expect(imports, hasLength(greaterThan(200)),
        reason: 'the lib/ traversal is not seeing real sources — the gates '
            'above are reporting a clean bill of health for an empty scan');

    for (final package in neutralPackages) {
      expect(imports.where((hit) => hit.package == package), isNotEmpty,
          reason: '$package contributed no scanned lines');
    }
  });

  group('the patterns match what they claim', () {
    // The teeth. Asserting an absence in real sources proves nothing about
    // whether the pattern would have caught a violation, so match them against
    // the real thing here.
    test('conditionalPattern', () {
      expect(
          conditionalPattern.hasMatch(
              "import 'a_stub.dart' if (dart.library.io) 'a_io.dart';"),
          isTrue);
      expect(
          conditionalPattern.hasMatch(
              "export 'x.dart' if ( dart.library.js_interop ) 'y.dart';"),
          isTrue,
          reason: 'whitespace inside the condition must not defeat the gate');
      expect(conditionalPattern.hasMatch("import 'dart:io';"), isFalse,
          reason: 'a plain platform import is the dep-tree walk\'s business, '
              'not this gate\'s');
    });

    test('throwingStubPattern', () {
      expect(throwingStubPattern.hasMatch("throw UnsupportedError('no');"),
          isTrue);
      expect(
          throwingStubPattern.hasMatch('throw UnimplementedError();'), isFalse);
      expect(throwingStubPattern.hasMatch('throws UnsupportedError if unset'),
          isFalse,
          reason: '"throws X" is prose; the gate wants the statement');
    });

    test('a throw wrapped across two lines is a known blind spot', () {
      // Stated rather than hidden. The scan is line-by-line, so a `throw` whose
      // argument moved to the next line is invisible to it. In practice
      // `dart format` keeps `throw UnsupportedError(` together because it fits,
      // and the dep-tree walk still covers the import that made the stub
      // necessary — so this is narrow, not load-bearing. If it ever matters,
      // the fix is to scan joined logical lines, not to widen the pattern.
      expect(throwingStubPattern.hasMatch('throw'), isFalse);
      expect(
          throwingStubPattern.hasMatch("    UnsupportedError('no');"), isFalse);
    });

    test('line comments are stripped before matching', () {
      // This, not the patterns, is what stops prose from failing the gate — and
      // these packages will accumulate a lot of prose about both constructs as
      // the port proceeds.
      expect(withoutLineComment('/// Do not throw UnsupportedError here.'), '');
      expect(
          withoutLineComment(
              "import 'a.dart' if (dart.library.io) 'b.dart'; // native"),
          "import 'a.dart' if (dart.library.io) 'b.dart'; ",
          reason: 'stripping a trailing comment must leave the directive');
      expect(
          throwingStubPattern
              .hasMatch(withoutLineComment('// throw UnsupportedError();')),
          isFalse);
    });
  });
}
