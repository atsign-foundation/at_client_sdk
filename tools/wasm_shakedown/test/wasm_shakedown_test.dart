// This suite reads the filesystem to inspect sources, so it runs on the VM only.
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

/// Unit tests for the walk itself.
///
/// Every `test/wasm/dep_tree_test.dart` in the repo rests on this code being
/// right: if the traversal stops early, or a package boundary resolves to the
/// wrong root, the baselines all record a comfortable fiction. So the pieces are
/// tested directly rather than only through the ratchets that consume them.
void main() {
  group('selectUri', () {
    test('takes the first branch whose condition holds', () {
      const clause = "'a_stub.dart' if (dart.library.io) 'a_io.dart'";
      expect(selectUri(clause, ioEnvironment), 'a_io.dart');
      expect(selectUri(clause, webEnvironment), 'a_stub.dart');
    });

    test('falls through to the default when no condition holds', () {
      // The case that matters most: a web build resolving a native seam takes
      // the stub, which is exactly what dart2wasm does — and why the walk finds
      // an unreachable dart:io import rather than reporting it as a violation.
      expect(
          selectUri(
              "'stub.dart' if (dart.library.io) 'io.dart'", webEnvironment),
          'stub.dart');
    });

    test('picks the first of several satisfied conditions', () {
      expect(
          selectUri(
              "'stub.dart' if (dart.library.js_interop) 'web.dart' "
              "if (dart.library.js_util) 'other.dart'",
              webEnvironment),
          'web.dart');
    });

    test('a plain uri has no branches', () {
      expect(selectUri("'package:at_commons/at_commons.dart'", webEnvironment),
          'package:at_commons/at_commons.dart');
    });

    test('web and io disagree about dart.library.io', () {
      // Pins the two environment constants against each other rather than
      // trusting each in isolation — a copy-paste that made webEnvironment a
      // second ioEnvironment would silence every gate at once.
      expect(webEnvironment['dart.library.io'], isFalse);
      expect(ioEnvironment['dart.library.io'], isTrue);
      expect(webEnvironment['dart.library.js_interop'], isTrue);
      expect(ioEnvironment['dart.library.js_interop'], isFalse);
    });
  });

  group('Shakedown', () {
    // Hand-built rather than walked, so the reporting logic is tested
    // independently of the traversal.
    final result = Shakedown(
      {
        '/w/packages/at_client/lib/src/a.dart': ['dart:io'],
        '/w/packages/at_client/lib/src/deep/b.dart': ['dart:ffi', 'dart:io'],
        '/w/packages/at_utils/lib/src/c.dart': ['dart:io'],
      },
      {
        'at_client': '/w/packages/at_client/lib/',
        'at_utils': '/w/packages/at_utils/lib/',
      },
      42,
      const [],
    );

    test('packageOf attributes by longest matching root', () {
      // Nested roots are the trap: a package whose lib/ path is a prefix of
      // another's would otherwise swallow its neighbour's offenders.
      final nested = Shakedown(
        {
          '/w/pkg/sub/lib/x.dart': ['dart:io']
        },
        {'outer': '/w/pkg/', 'inner': '/w/pkg/sub/lib/'},
        1,
        const [],
      );
      expect(nested.packageOf('/w/pkg/sub/lib/x.dart'), 'inner');
    });

    test('offendersIn keys paths relative to the package', () {
      expect(result.offendersIn('at_client'), {
        'lib/src/a.dart': ['dart:io'],
        'lib/src/deep/b.dart': ['dart:ffi', 'dart:io'],
      });
    });

    test('offendersIn is empty for a package with no root', () {
      expect(result.offendersIn('at_nonexistent'), isEmpty);
    });

    test('blockedPackages is the owning set', () {
      expect(result.blockedPackages, {'at_client', 'at_utils'});
    });

    test('report names the owning package for every offender', () {
      expect(result.report(), contains('at_client:'));
      expect(result.report(), contains('at_utils:'));
      expect(result.report(), contains('dart:ffi'));
    });
  });

  group('the walk, against the real workspace', () {
    test('at_commons is neutral, and the walk proves it by traversing', () {
      // at_commons is the one package beneath at_client with no platform import
      // anywhere, which makes it the honest positive control: a green result
      // here is a real green, not a stalled walk.
      final result = shakedown('package:at_commons/at_commons.dart');

      expect(result.offenders, isEmpty, reason: result.report());
      expect(result.missingFiles, isEmpty,
          reason: 'imported but not found: ${result.missingFiles}');
      expect(result.filesWalked, greaterThan(20),
          reason: 'the walk stopped early — package resolution is broken, and '
              'every baseline in the repo is measuring nothing');
    });

    test('a platform library in the graph is reported', () {
      // The negative control. at_utils.dart exports app_config.dart and
      // pseudo_server_socket.dart, both dart:io, so a walk that reports nothing
      // here is broken regardless of what it says elsewhere.
      final result = shakedown('package:at_utils/at_utils.dart');
      expect(result.offendersIn('at_utils'), isNotEmpty,
          reason: 'the walk found no dart:io under at_utils.dart, which is '
              'known to reach it — the traversal or the forbidden set is wrong');
    });

    test('an unresolvable package is an error, not a clean result', () {
      expect(() => shakedown('package:not_a_real_package/x.dart'),
          throwsA(isA<ArgumentError>()));
    });

    test('a barrel that no longer exists shows up in missingFiles', () {
      // The other way a gate can be silently defanged: the package resolves, the
      // file does not, and the walk has nothing to report. `missingFiles` is why
      // every dep_tree_test.dart asserts it is empty — without that assertion, a
      // renamed barrel reads as a clean bill of health.
      final result = shakedown('package:at_client/does_not_exist.dart');
      expect(result.offenders, isEmpty);
      expect(result.missingFiles, hasLength(1));
    });
  });
}
