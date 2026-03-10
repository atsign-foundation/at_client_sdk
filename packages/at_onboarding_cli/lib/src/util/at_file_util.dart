import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_utils/at_logger.dart';

/// Utility class for file system operations.
class AtFileUtil {
  static final AtSignLogger _logger = AtSignLogger('AtFileUtil');

  /// Sets secure file permissions (owner read/write only).
  ///
  /// On POSIX systems, uses chmod 600.
  ///
  /// On Windows, uses icacls to remove inherited permissions and grant full
  /// control only to the current user.
  static Future<void> setSecureFilePermissions(String filePath) async {
    try {
      if (Platform.isWindows) {
        _logger.finer('Setting secure permissions on file: $filePath');
        final username =
            Platform.environment['USERNAME'] ?? Platform.environment['USER'];
        if (username == null) {
          throw StateError('Could not determine username');
        }

        final result = await Process.run('icacls', [
          filePath,
          '/inheritance:r',
          '/grant:r',
          '$username:F',
        ]);

        if (result.exitCode != 0) {
          _logger.warning('icacls failed: ${result.stderr}');
        }
      } else if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
        await Process.run('chmod', ['600', filePath]);
      } else {
        _logger.warning(
            'Unsupported platform: ${Platform.operatingSystem}');
      }
    } catch (e) {
      _logger.warning('Could not set file permissions on $filePath | $e');
    }
  }

  /// Checks if the specified [file] is writable and does not already exist.
  ///
  /// This function attempts to create the directories for the given [file] if they do not exist,
  /// and then tries to open the file in write mode to verify write permissions.
  /// If the file can be opened for writing, it is immediately closed and deleted.
  ///
  /// Throws a [PathExistsException] if [file] already exists, a
  /// [PathAccessException] if the path lacks write permissions, or the
  /// underlying platform exception for any other I/O failure.
  static void ensureWritable(File file) {
    try {
      // If the directories do not exist, create them.
      // "recursive" is set to true to ensure that any missing parent directories are created.
      // "exclusive" is set to true to prevent creation of file if it already exists.
      file.createSync(recursive: true, exclusive: true);
      // Try opening the file in write mode, which requires write permissions
      RandomAccessFile raf = file.openSync(mode: FileMode.write);
      raf.closeSync();
      // Deletes only if the new file is created to verify write permissions.
      file.deleteSync();
    } on PathExistsException {
      throw AtKeysFileOverwriteException('Keys file already exists at ${file.path}');
    } on PathAccessException {
      stderr.writeln('Path: ${file.path} does not have write permissions');
      rethrow;
    } catch (e) {
      stderr.writeln('Error in writing keys file to path: ${file.path}');
      rethrow;
    }
  }
}