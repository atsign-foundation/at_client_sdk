import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

const String defaultPathUniqueID = 'singleton';

/// Generate a path like this:
/// $baseDir/.atsign/storage/$atSign/$progName/$uniqueID
/// (normalized to use platform-specific path separator)
String standardAtClientStoragePath({
  required String baseDir,
  required String atSign,
  required String progName, // e.g. npt, sshnp, sshnpd, srvd etc
  String uniqueID = defaultPathUniqueID,
}) {
  return path.normalize('$baseDir'
          '/.atsign'
          '/storage'
          '/$atSign'
          '/$progName'
          '/$uniqueID'
      .replaceAll('/', Platform.pathSeparator));
}

@visibleForTesting
Directory standardWindowsAtClientStorageDir({
  required String atSign,
  required String progName, // e.g. npt, sshnp, sshnpd, srvd etc
  required String uniqueID,
}) {
  return Directory(standardAtClientStoragePath(
    baseDir: Platform.environment['TEMP']!,
    atSign: atSign,
    progName: progName,
    uniqueID: uniqueID,
  ));
}

/// Generate a path like this:
/// $baseDir/.atsign/storage/$atSign/$progName/$uniqueID
/// (normalized to use platform-specific path separator)
/// where baseDir is either
/// - for Windows: `Platform.environment['TEMP']`
/// - for others: [getHomeDirectory]
Directory standardAtClientStorageDir({
  required String atSign,
  required String progName, // e.g. npt, sshnp, sshnpd, srvd etc
  required String uniqueID,
}) {
  if (Platform.isWindows) {
    return standardAtClientStorageDir(
      atSign: atSign,
      progName: progName,
      uniqueID: uniqueID,
    );
  } else {
    return Directory(standardAtClientStoragePath(
      baseDir: getHomeDirectory()!,
      atSign: atSign,
      progName: progName,
      uniqueID: uniqueID,
    ));
  }
}

/// Get the home directory or null if unknown.
String? getHomeDirectory({bool throwIfNull = false}) {
  String? homeDir;
  switch (Platform.operatingSystem) {
    case 'linux':
    case 'macos':
      homeDir = Platform.environment['HOME'];
      break;

    case 'windows':
      homeDir = Platform.environment['USERPROFILE'];
      break;

    case 'android':
      // Probably want internal storage.
      homeDir = '/storage/sdcard0';
      break;

    case 'ios':
    // iOS doesn't really have a home directory.
    case 'fuchsia':
    // I have no idea.
    default:
      homeDir = null;
  }
  if (throwIfNull && homeDir == null) {
    throw ('\nUnable to determine your home directory: please set environment variable\n\n');
  }
  return homeDir;
}

/// Get the local username, or null if it cannot be determined.
///
/// Resolves in order: the `USER`, `LOGNAME`, then `USERNAME` environment
/// variables, then an OS query (`whoami`). Process supervisors such as Docker,
/// systemd without `User=`, and network-OS app managers often leave those
/// variables unset, so the OS query is the reliable last resort. When
/// [throwIfNull] is true and none of the sources yields a value, throws a
/// message naming the variable to set rather than returning null (which
/// crashes callers that use `!`).
String? getUserName({bool throwIfNull = false}) =>
    resolveUserName(Platform.environment, throwIfNull: throwIfNull);

/// The testable core of [getUserName]: resolves a username from [environment]
/// (`USER` → `LOGNAME` → `USERNAME`), then from [osLookup] (defaults to
/// `whoami`). Empty values are treated as absent.
@visibleForTesting
String? resolveUserName(
  Map<String, String> environment, {
  bool throwIfNull = false,
  String? Function()? osLookup,
}) {
  for (final name in const ['USER', 'LOGNAME', 'USERNAME']) {
    final value = environment[name];
    if (value != null && value.isNotEmpty) return value;
  }
  final fromOs = (osLookup ?? _whoami)();
  if (fromOs != null && fromOs.isNotEmpty) return fromOs;
  if (throwIfNull) {
    throw ('\nUnable to determine your username: '
        'please set the USER (or LOGNAME) environment variable\n\n');
  }
  return null;
}

/// Ask the OS for the current username via `whoami`. Returns null if `whoami`
/// is unavailable (e.g. a minimal container) or produces no output.
String? _whoami() {
  try {
    final result = Process.runSync('whoami', const <String>[]);
    if (result.exitCode == 0) {
      final name = (result.stdout as String).trim();
      if (name.isNotEmpty) return name;
    }
  } on ProcessException {
    // `whoami` not on PATH — fall through to null.
  }
  return null;
}

Future<bool> fileExists(String file) async {
  bool f = await File(file).exists();
  return f;
}

bool checkNonAscii(String test) {
  var extra = test.replaceAll(RegExp(r'[a-zA-Z0-9_]*'), '');
  if ((extra != '') || (test.length > 15)) {
    return true;
  } else {
    return false;
  }
}

/// $homeDirectory/.atsign/keys/${atSign}_key.atKeys
String getDefaultAtKeysFilePath(String homeDirectory, String atSign) {
  return '$homeDirectory/.atsign/keys/${atSign}_key.atKeys'
      .replaceAll('/', Platform.pathSeparator);
}

/// '$homeDirectory/.ssh/'
String getDefaultSshDirectory(String homeDirectory) {
  return '$homeDirectory/.ssh/'.replaceAll('/', Platform.pathSeparator);
}

/// Checks if the provided atSign's atServer has been properly activated with a public RSA key.
/// `atClient` must be authenticated
/// `atSign` is the atSign to check
/// Returns `true`, if the atSign's cloud secondary server has an existing `public:publickey@` in their server,
/// Returns `false`, if the atSign's cloud secondary *exists*, but does not have an existing `public:publickey@`
/// Throws [AtClientException] if the cloud secondary is invalid or not reachable
Future<bool> atSignIsActivated(final AtClient atClient, String atSign) async {
  final Metadata metadata = Metadata()
    ..isPublic = true
    ..namespaceAware = false;

  final AtKey publicKey = AtKey()
    ..sharedBy = atSign
    ..key = 'publickey'
    ..metadata = metadata;

  try {
    await atClient.get(publicKey);
    return true;
  } catch (e) {
    if (e is AtKeyNotFoundException ||
        (e is AtClientException &&
            e.message.contains("public:publickey") &&
            e.message.contains("does not exist in keystore"))) {
      return false;
    }
    rethrow;
  }
}
