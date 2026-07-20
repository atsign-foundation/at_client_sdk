import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:test/test.dart';

void main() {
  String atSign = '@alice';
  String progName = 'test';
  String uniqueID = '${DateTime.now().millisecondsSinceEpoch}';

  test('test standardAtClientStoragePath without uniqueID', () {
    expect(
        standardAtClientStoragePath(
          baseDir: '/tmp',
          atSign: '@alice',
          progName: 'test',
        ),
        '/tmp/.atsign/storage/$atSign/$progName/$defaultPathUniqueID'
            .replaceAll('/', Platform.pathSeparator));
  });

  test('test standardAtClientStoragePath with uniqueID', () {
    expect(
        standardAtClientStoragePath(
          baseDir: '/tmp',
          atSign: '@alice',
          progName: 'test',
          uniqueID: uniqueID,
        ),
        '/tmp/.atsign/storage/$atSign/$progName/$uniqueID'
            .replaceAll('/', Platform.pathSeparator));
  });

  test('test standardAtClientStorageDir', () {
    Directory dir = standardAtClientStorageDir(
      atSign: atSign,
      progName: progName,
      uniqueID: uniqueID,
    );
    if (Platform.isWindows) {
      expect(
          dir,
          standardWindowsAtClientStorageDir(
            atSign: atSign,
            progName: progName,
            uniqueID: uniqueID,
          ));
    } else {
      expect(
          dir.path,
          '${getHomeDirectory()}/.atsign/storage/$atSign/$progName/$uniqueID'
              .replaceAll('/', Platform.pathSeparator));
    }
  });

  group('resolveUserName', () {
    // A stub OS lookup so tests never spawn `whoami` and stay deterministic.
    String? never() => null;

    test('returns USER when set', () {
      expect(resolveUserName({'USER': 'alice'}, osLookup: never), 'alice');
    });

    test('falls back to LOGNAME when USER is unset', () {
      expect(resolveUserName({'LOGNAME': 'bob'}, osLookup: never), 'bob');
    });

    test('falls back to USERNAME when USER and LOGNAME are unset', () {
      expect(resolveUserName({'USERNAME': 'carol'}, osLookup: never), 'carol');
    });

    test('USER takes precedence over LOGNAME and USERNAME', () {
      expect(
          resolveUserName(
              {'USER': 'alice', 'LOGNAME': 'bob', 'USERNAME': 'carol'},
              osLookup: never),
          'alice');
    });

    test('an empty env var is treated as absent and skipped', () {
      expect(resolveUserName({'USER': '', 'LOGNAME': 'bob'}, osLookup: never),
          'bob');
    });

    test('falls back to the OS lookup when no env var yields a value', () {
      expect(resolveUserName({}, osLookup: () => 'dave'), 'dave');
    });

    test('an empty OS-lookup result is treated as no value', () {
      expect(resolveUserName({'USER': ''}, osLookup: () => ''), isNull);
    });

    // The bug this fixes: the throwIfNull branch was unreachable on
    // Linux/macOS, so an unset USER flowed to callers' `!` as a bare null.
    test('returns null (does not throw) when unresolved and throwIfNull=false',
        () {
      expect(resolveUserName({}, osLookup: never), isNull);
    });

    test('throws a helpful message when unresolved and throwIfNull=true', () {
      expect(
        () => resolveUserName({}, throwIfNull: true, osLookup: never),
        throwsA(allOf(isA<String>(), contains('USER'))),
      );
    });

    test('does NOT throw when resolvable even if throwIfNull=true', () {
      expect(
          resolveUserName({'USER': 'alice'},
              throwIfNull: true, osLookup: never),
          'alice');
    });

    test('default OS lookup (real whoami) resolves when the env is empty', () {
      // The reported bug (unset USER under Docker/systemd/network-OS): with no
      // env vars, the default path must fall back to `whoami` and still find
      // the user — the whole point of the fix. Skipped where `whoami` is
      // unavailable or formats differently (Windows: domain\\user).
      if (Platform.isWindows) return;
      final ProcessResult probe;
      try {
        probe = Process.runSync('whoami', const <String>[]);
      } on ProcessException {
        return; // no whoami on this host — nothing to assert
      }
      if (probe.exitCode != 0) return;
      final expected = (probe.stdout as String).trim();
      expect(resolveUserName(const {}), expected);
    });
  });

  group('getUserName', () {
    test('never throws when throwIfNull is false (default)', () {
      // On any host this must return without throwing (null or a value).
      expect(() => getUserName(), returnsNormally);
    });
  });
}
