import 'dart:io';

import 'package:at_utils/at_utils.dart';

/// The one directory every `.atKeys` file this package generates is allowed to
/// live in, and the only place a test may get a keyfile path from.
///
/// ⚠️ Set `AtOnboardingPreference.atKeysFilePath` from [testKeysFile] on every
/// preference and pass `-k` to every `auth_cli` invocation: both fall back to
/// `~/.atsign/keys`, which on a developer machine holds live personal keyfiles
/// a test would overwrite.
///
/// Emptied when a test process first asks for it rather than in a tearDown, so
/// an aborted run cannot poison the next one; that relies on
/// `dart test --concurrency=1`.
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
