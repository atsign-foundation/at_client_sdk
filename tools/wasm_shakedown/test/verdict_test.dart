// Pure unit tests, but the walk type they judge reaches dart:io, so VM only.
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:wasm_shakedown/verdict.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

/// A walk, written down rather than taken — which is what makes the baseline
/// logic testable. Both gated packages baseline an empty allow list over a
/// package owning no offender, so both directions of the subtraction are empty
/// against the live tree.
Shakedown _walk({
  Map<String, List<String>> offenders = const {},
  int filesWalked = 900,
  List<String> missingFiles = const [],
  Map<String, String> roots = const {
    'at_auth': '/w/packages/at_auth/lib/',
    'at_utils': '/w/packages/at_utils/lib/',
  },
}) =>
    Shakedown(offenders, roots, filesWalked, missingFiles);

/// An offender map keyed by at_auth-relative path, for brevity below.
Map<String, List<String>> _atAuth(Map<String, List<String>> relative) => {
      for (final e in relative.entries)
        '/w/packages/at_auth/lib/${e.key.substring('lib/'.length)}': e.value,
    };

RatchetVerdict _ratchet(
  Shakedown walk, {
  String package = 'at_auth',
  Set<String> allowed = const {},
  int maxBlocked = 4,
  int minWalked = 850,
}) =>
    RatchetVerdict(walk,
        barrel: 'package:at_auth/at_auth.dart',
        package: package,
        allowedOffenders: allowed,
        maxBlockedPackages: maxBlocked,
        minFilesWalked: minWalked);

ControlVerdict _control(
  Shakedown walk, {
  String? reachesFile,
  String? reachesLibrary,
}) =>
    ControlVerdict(walk,
        barrel: 'package:at_auth/at_auth_io.dart',
        package: 'at_auth',
        because: 'the filesystem code it exists to quarantine',
        reachesFile: reachesFile,
        reachesLibrary: reachesLibrary);

void main() {
  group('RatchetVerdict — the allow list', () {
    test(
        'added subtracts the baseline from the walk, not the walk from the '
        'baseline', () {
      // Owned {a}, allowed {b}: correct reports a, reversed reports nothing
      // and every gate in the repo stays green.
      final verdict = _ratchet(
        _walk(
            offenders: _atAuth({
          'lib/a.dart': ['dart:io']
        })),
        allowed: const {'lib/b.dart'},
      );

      expect(verdict.added, ['lib/a.dart']);
      expect(verdict.noNewOffenders, isFalse);
    });

    test('a source outside the allow list is added', () {
      final verdict = _ratchet(_walk(
          offenders: _atAuth({
        'lib/rogue.dart': ['dart:io']
      })));
      expect(verdict.added, ['lib/rogue.dart']);
    });

    test('a listed source is not added', () {
      final verdict = _ratchet(
        _walk(
            offenders: _atAuth({
          'lib/known.dart': ['dart:io']
        })),
        allowed: const {'lib/known.dart'},
      );
      expect(verdict.added, isEmpty);
      expect(verdict.holds, isTrue);
    });

    test(
        'an allow-list entry the walk no longer reaches passes, and the figure '
        'says the baseline went loose', () {
      // Nothing fails; 0/1 is what says a listed path is now dead weight.
      final verdict = _ratchet(_walk(), allowed: const {'lib/fixed.dart'});

      expect(verdict.added, isEmpty);
      expect(verdict.holds, isTrue);
      expect(verdict.figure, contains('0/1 offenders'));
    });

    test('an offender in another package is not this package\'s to answer for',
        () {
      final verdict = _ratchet(_walk(offenders: {
        '/w/packages/at_utils/lib/src/c.dart': ['dart:io'],
      }));
      expect(verdict.owned, isEmpty);
      expect(verdict.added, isEmpty);
    });

    test('added is sorted, so the message reads in a stable order', () {
      final verdict = _ratchet(_walk(
          offenders: _atAuth({
        'lib/z.dart': ['dart:io'],
        'lib/a.dart': ['dart:io'],
        'lib/m.dart': ['dart:io'],
      })));
      expect(verdict.added, ['lib/a.dart', 'lib/m.dart', 'lib/z.dart']);
    });

    test('the message names every added path, the file count and the walk', () {
      final verdict = _ratchet(_walk(
        offenders: _atAuth({
          'lib/one.dart': ['dart:io']
        }),
        filesWalked: 969,
      ));
      expect(verdict.newOffenderMessage, contains('lib/one.dart'));
      expect(verdict.newOffenderMessage, contains('969 files'));
      expect(verdict.newOffenderMessage, contains('at_auth'));
    });
  });

  group('RatchetVerdict — the blocked ceiling', () {
    Shakedown blockedIn(int packages) => _walk(offenders: {
          for (var i = 0; i < packages; i++)
            '/w/packages/p$i/lib/x.dart': ['dart:io'],
        }, roots: {
          for (var i = 0; i < packages; i++) 'p$i': '/w/packages/p$i/lib/',
          'at_auth': '/w/packages/at_auth/lib/',
        });

    test('a count over the ceiling fails', () {
      final verdict = _ratchet(blockedIn(5), maxBlocked: 4);
      expect(verdict.underCeiling, isFalse);
    });

    test('a count exactly at the ceiling passes', () {
      // `<=`, so four against a ceiling of four is green.
      expect(_ratchet(blockedIn(4), maxBlocked: 4).underCeiling, isTrue);
    });

    test('a count under the ceiling passes', () {
      expect(_ratchet(blockedIn(2), maxBlocked: 4).underCeiling, isTrue);
    });

    test('the message names the blocked packages, sorted', () {
      final verdict = _ratchet(
        _walk(
          offenders: {
            '/w/packages/at_utils/lib/c.dart': ['dart:io'],
            '/w/packages/at_auth/lib/a.dart': ['dart:io'],
          },
        ),
        maxBlocked: 0,
      );
      expect(verdict.ceilingMessage, contains('at_auth, at_utils'));
    });
  });

  group('RatchetVerdict — the traversal guard', () {
    test('a file count below minFilesWalked fails', () {
      expect(
          _ratchet(_walk(filesWalked: 10), minWalked: 850).deepEnough, isFalse);
    });

    test('a file count exactly at minFilesWalked fails', () {
      // Pins `greaterThan`, and why the message says "requires more than".
      expect(_ratchet(_walk(filesWalked: 850), minWalked: 850).deepEnough,
          isFalse);
    });

    test('a file count above minFilesWalked passes', () {
      expect(
          _ratchet(_walk(filesWalked: 851), minWalked: 850).deepEnough, isTrue);
    });

    test('the shallow-walk message names both figures', () {
      final verdict = _ratchet(_walk(filesWalked: 3), minWalked: 850);
      expect(verdict.shallowWalkMessage, contains('only 3 files'));
      expect(verdict.shallowWalkMessage, contains('more than 850'));
    });

    test('a missing file fails, and the message names it', () {
      final verdict = _ratchet(_walk(missingFiles: const ['/w/gone.dart']));
      expect(verdict.nothingMissing, isFalse);
      expect(verdict.missingFilesMessage, contains('/w/gone.dart'));
    });

    test('no missing files passes', () {
      expect(_ratchet(_walk()).nothingMissing, isTrue);
    });
  });

  group('RatchetVerdict — the package name', () {
    test(
        'a package the config does not know is a misconfiguration, not a '
        'clean bill of health', () {
      final verdict = _ratchet(_walk(), package: 'at_chpos');
      expect(verdict.packageKnown, isFalse);
      expect(verdict.holds, isFalse);
      expect(verdict.unknownPackageMessage, contains('at_chpos'));
    });

    test('an unknown package name still reports an empty owned set', () {
      // Why packageKnown exists: every other check is satisfied by a walk
      // attributed to a package that is not in the graph.
      final verdict = _ratchet(
        _walk(
            offenders: _atAuth({
          'lib/a.dart': ['dart:io']
        })),
        package: 'at_chpos',
      );
      expect(verdict.owned, isEmpty);
      expect(verdict.noNewOffenders, isTrue);
      expect(verdict.deepEnough, isTrue);
    });

    test('a resolved package name passes', () {
      expect(_ratchet(_walk()).packageKnown, isTrue);
    });
  });

  group('RatchetVerdict — the figure line', () {
    test('the figure reads barrel, files walked, offenders and blocked', () {
      // Exact equality: printed on every run and the only loose-baseline
      // signal, so the format is an artifact, not a detail.
      final verdict = _ratchet(
        _walk(
            offenders: _atAuth({
          'lib/a.dart': ['dart:io']
        })),
        allowed: const {'lib/a.dart'},
        maxBlocked: 4,
      );
      expect(
          verdict.figure,
          'package:at_auth/at_auth.dart — 900 files walked, '
          '1/1 offenders, 1/4 blocked');
    });

    test('the figure reports a loose baseline as 1/2 offenders', () {
      final verdict = _ratchet(
        _walk(
            offenders: _atAuth({
          'lib/a.dart': ['dart:io']
        })),
        allowed: const {'lib/a.dart', 'lib/fixed.dart'},
      );
      expect(verdict.figure, contains('1/2 offenders'));
    });

    test('a failing verdict still has a figure line', () {
      final verdict = _ratchet(_walk(filesWalked: 1));
      expect(verdict.holds, isFalse);
      expect(verdict.figure, contains('1 files walked'));
    });
  });

  group('RatchetVerdict — holds and failures', () {
    test('a walk at its baseline holds, and reports no failures', () {
      final verdict = _ratchet(_walk());
      expect(verdict.holds, isTrue);
      expect(verdict.failures, isEmpty);
    });

    test('every failing check contributes exactly one message', () {
      // A check that fails without prose fails silently.
      final verdict = _ratchet(
        _walk(
          offenders: _atAuth({
            'lib/a.dart': ['dart:io']
          }),
          filesWalked: 2,
          missingFiles: const ['/w/gone.dart'],
        ),
        package: 'at_chpos',
        maxBlocked: 0,
      );
      // noNewOffenders is satisfied vacuously by the unknown package, so four
      // of the five fail: ceiling, packageKnown, nothingMissing, deepEnough.
      expect(verdict.failures, hasLength(4));
    });
  });

  group('ControlVerdict', () {
    final reaching = _walk(
        offenders: _atAuth({
      'lib/src/keys/io/file_io.dart': ['dart:io'],
    }));

    test('a file among the package offenders passes', () {
      final verdict =
          _control(reaching, reachesFile: 'lib/src/keys/io/file_io.dart');
      expect(verdict.holds, isTrue);
      expect(verdict.failures, isEmpty);
    });

    test('a file absent from the offenders fails', () {
      final verdict = _control(reaching, reachesFile: 'lib/src/moved.dart');
      expect(verdict.holds, isFalse);
      expect(verdict.failures.single, contains('lib/src/moved.dart'));
    });

    test(
        'a file is matched whole, so a longer path does not satisfy a shorter '
        'one', () {
      expect(_control(reaching, reachesFile: 'lib/src/keys').holds, isFalse);
    });

    test('a library reached by the package passes', () {
      expect(_control(reaching, reachesLibrary: 'dart:io').holds, isTrue);
    });

    test('a library reached only by a dependency fails', () {
      // Scoped to offendersIn(package): at_utils reaching dart:io says
      // nothing about at_auth's island.
      final verdict = _control(
        _walk(offenders: {
          '/w/packages/at_utils/lib/c.dart': ['dart:io']
        }),
        reachesLibrary: 'dart:io',
      );
      expect(verdict.holds, isFalse);
    });

    test('a library is matched whole, so dart:js_util does not satisfy dart:js',
        () {
      final verdict = _control(
        _walk(
            offenders: _atAuth({
          'lib/a.dart': ['dart:js_util']
        })),
        reachesLibrary: 'dart:js',
      );
      expect(verdict.holds, isFalse);
    });

    test('both axes must hold when both are named', () {
      expect(
          _control(reaching,
                  reachesFile: 'lib/src/keys/io/file_io.dart',
                  reachesLibrary: 'dart:ffi')
              .holds,
          isFalse);
      expect(
          _control(reaching,
                  reachesFile: 'lib/src/keys/io/file_io.dart',
                  reachesLibrary: 'dart:io')
              .holds,
          isTrue);
    });

    test('an axis left out is absent from the checks, not a passing one', () {
      final verdict = _control(reaching, reachesLibrary: 'dart:io');
      expect(verdict.fileReached, isNull);
      expect(verdict.libraryReached, isTrue);
    });

    test('a control naming neither axis is refused', () {
      expect(() => _control(reaching), throwsA(isA<ArgumentError>()));
    });

    test('a stalled walk fails a control, with no minimum file count', () {
      // The asymmetry with RatchetVerdict: positive checks need no floor.
      final verdict = _control(_walk(filesWalked: 1),
          reachesFile: 'lib/src/keys/io/file_io.dart',
          reachesLibrary: 'dart:io');
      expect(verdict.holds, isFalse);
      expect(verdict.failures.single, contains('1 files'));
      expect(verdict.failures.single, contains('(none'));
    });

    test('the message names the target, the reason and what was found', () {
      final verdict = _control(reaching, reachesFile: 'lib/src/moved.dart');
      expect(verdict.failures.single, contains('lib/src/moved.dart'));
      expect(verdict.failures.single, contains('exists to quarantine'));
      expect(verdict.failures.single, contains('lib/src/keys/io/file_io.dart'));
    });
  });
}
