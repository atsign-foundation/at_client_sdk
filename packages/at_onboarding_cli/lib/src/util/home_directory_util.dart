import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:path/path.dart' as path;

class HomeDirectoryUtil {
  static const String defaultPathUniqueID = 'singleton';

  static final homeDir = getHomeDirectory();

  static String? getHomeDirectory() {
    switch (Platform.operatingSystem) {
      case 'linux':
      case 'macos':
        return Platform.environment['HOME'];
      case 'windows':
        return Platform.environment['USERPROFILE'];
      case 'android':
        // Probably want internal storage.
        return '/storage/sdcard0';
      default:
        return null;
    }
  }

  static String getAtKeysPath(String atsign) {
    if (homeDir == null) {
      throw AtClientException.message('Could not find home directory');
    }
    return path.join(homeDir!, '.atsign', 'keys', '${atsign}_key.atKeys');
  }

  static String getStorageDirectory(String atsign, {String? enrollmentId}) {
    if (homeDir == null) {
      throw AtClientException.message('Could not find home directory');
    }
    if (enrollmentId != null) {
      return path.join(homeDir!, '.atsign', 'at_onboarding_cli', 'storage',
          atsign, enrollmentId);
    }
    return path.join(
        homeDir!, '.atsign', 'at_onboarding_cli', 'storage', atsign);
  }

  static String getCommitLogPath(String atsign, {String? enrollmentId}) {
    return path.join(
        getStorageDirectory(atsign, enrollmentId: enrollmentId), 'commitLog');
  }

  static String getHiveStoragePath(String atsign, {String? enrollmentId}) {
    return path.join(
        HomeDirectoryUtil.getStorageDirectory(atsign,
            enrollmentId: enrollmentId),
        'hive');
  }

  /// Generate a path like this:
  /// $baseDir/.atsign/storage/$atSign/$progName/$uniqueID
  /// (normalized to use platform-specific path separator)
  static String standardAtClientStoragePath({
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

  static Directory standardWindowsAtClientStorageDir({
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
  static Directory standardAtClientStorageDir({
    required String atSign,
    required String progName, // e.g. npt, sshnp, sshnpd, srvd etc
    required String uniqueID,
  }) {
    if (Platform.isWindows) {
      return standardWindowsAtClientStorageDir(
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

  static String getDefaultTempDir() {
    final parentDir = getHomeDirectory() ?? Directory.systemTemp.path;
    return path.join(parentDir, '.atsign', 'tmp');
  }

  static String getDefaultTempFilePath(String atSign,
      {String? parentDir, String? uniqueId}) {
    return path.join(
        parentDir ?? getDefaultTempDir(), '${atSign}_$uniqueId.tmp');
  }
}
