import 'package:test/test.dart';
import 'package:wasm_shakedown/wasm_shakedown.dart';

/// Dependency-tree shakedown for at_utils' web-safe barrels.
///
/// at_utils sits under `at_chops`, `at_auth`, `at_lookup` and `at_client`, so a
/// `dart:io` leak here reaches all of them. Two of its four barrels are web-safe
/// and two are deliberately not; this pins which is which.
///
/// | Barrel             | Web-safe | Why                                        |
/// | ------------------ | -------- | ------------------------------------------ |
/// | `at_logger.dart`   | yes      | handlers split behind `dart.library.io`     |
/// | `at_progress.dart` | yes      | colour moved to the CLI barrel              |
/// | `at_utils.dart`    | **no**   | exports app_config + pseudo_server_socket   |
/// | `at_utils_cli.dart`| **no**   | chalkdart, on purpose — CLIs only           |
///
/// The walk lives in `tools/wasm_shakedown`; this file is only at_utils' entry
/// points and expectations.
void main() {
  group('web-safe barrels are clean', () {
    for (final barrel in ['at_logger.dart', 'at_progress.dart']) {
      test(barrel, () {
        final result = shakedown('package:at_utils/$barrel');

        // Not just at_utils-owned: nothing anywhere in these graphs may name a
        // browser-hostile library. at_utils' web barrels reach only at_commons,
        // collection, logging and crypto, all of which are clean today — so the
        // strong assertion is affordable here in a way it is not for at_auth.
        expect(result.blockedPackages, isEmpty,
            reason: 'package:at_utils/$barrel reaches code a browser cannot '
                'run:\n${result.report()}');
        expect(result.missingFiles, isEmpty,
            reason: 'imported but not found: ${result.missingFiles}');
        expect(result.filesWalked, greaterThan(5),
            reason: 'walk stopped early — resolution is probably broken');
      });
    }
  });

  group('native-only barrels really are native-only', () {
    // The inverse half of each seam. Without these the tests above could pass
    // because a barrel quietly collapsed into its own stub.

    test('at_utils.dart still carries the dart:io utilities', () {
      final owned =
          shakedown('package:at_utils/at_utils.dart').offendersIn('at_utils');
      expect(owned.keys, contains('lib/src/config/app_config.dart'));
      expect(
          owned.keys, contains('lib/src/networking/pseudo_server_socket.dart'));
    });

    test('at_utils_cli.dart carries chalkdart when dart.library.io is true',
        () {
      // Must be walked with io semantics: at_utils_cli.dart is conditional (so
      // it resolves to the same library as the back-compat re-exports in
      // at_logger/at_progress, avoiding an ambiguous-import error), which means
      // a web-semantics walk would follow the stub and find nothing.
      final io = shakedown('package:at_utils/at_utils_cli.dart',
          environment: ioEnvironment);
      expect(io.blockedPackages, contains('chalkdart'),
          reason: 'the CLI barrel no longer reaches chalk — either colour was '
              'dropped, or the conditional collapsed to the stub on both '
              'platforms:\n${io.report()}');
    });

    test('the back-compat re-exports do not drag chalk into the web barrels',
        () {
      // The specific regression this design exists to prevent: at_logger.dart
      // and at_progress.dart re-export CLILoggingHandler and ChalkFunction for
      // compatibility, and must resolve to the uncoloured stubs on web.
      for (final barrel in ['at_logger.dart', 'at_progress.dart']) {
        final web = shakedown('package:at_utils/$barrel');
        expect(web.blockedPackages, isNot(contains('chalkdart')),
            reason: '$barrel pulls chalkdart on web:\n${web.report()}');
      }
    });
  });
}
