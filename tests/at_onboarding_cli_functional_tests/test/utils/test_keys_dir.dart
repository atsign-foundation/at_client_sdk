import 'dart:io';

import 'package:at_utils/at_utils.dart';

/// The one directory every `.atKeys` file this package generates is allowed to
/// live in, and the only place a test may get a keyfile path from.
///
/// **Never name `~/.atsign/keys` in this package.** That is where
/// `at_onboarding_cli` puts keyfiles when `AtOnboardingPreference.atKeysFilePath`
/// is left null, and on a developer machine it holds live personal keyfiles for
/// real atSigns. A test that writes there overwrites them, and the demo-atSign
/// files it leaves behind fail the *next* run with "Keys file already exists",
/// because onboarding and enrollment both refuse to overwrite an existing
/// keyfile. Set `atKeysFilePath` explicitly — from [testKeysFile] — on every
/// preference, and pass `-k` to every `auth_cli` invocation; a preference that
/// omits it silently gets the home-directory default.
///
/// The directory is emptied when a test process first asks for it, not in a
/// tearDown, so an aborted or crashed run cannot poison the next one.
///
/// Relies on `dart test --concurrency=1` (the rule everywhere in this tree, and
/// what CI runs) so that one test file's purge cannot land mid-run of another.
/// The rest of this package already assumes serial execution — it shares
/// `storage/` and `test/storage/` the same way.
String get testKeysDir => _keysDir.path;

/// Absolute path for `<atSign>_<suffix>.atKeys` inside [testKeysDir].
String testKeysFile(String atSign, {String suffix = 'key'}) =>
    '${_keysDir.path}${Platform.pathSeparator}'
    '${AtUtils.fixAtSign(atSign)}_$suffix.atKeys';

/// Resolved against the package root, which is the working directory both
/// `dart test` and the CI job use.
final Directory _keysDir = _emptiedKeysDir();

Directory _emptiedKeysDir() {
  final dir = Directory('test/.tmp_keys').absolute;
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
  dir.createSync(recursive: true);
  return dir;
}
