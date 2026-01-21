import 'dart:io';

import 'package:at_utils/at_logger.dart';

/// Utility class for file system operations.
class AtFileUtil {
  static final AtSignLogger _logger = AtSignLogger('AtFileUtil');

  /// Sets secure file permissions (owner read/write only).
  ///
  /// On POSIX systems, uses chmod 600.
  /// On Windows, uses icacls to remove inherited permissions and grant full control only to the current user.
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
          '/remove:g',
          'Everyone',
          '/remove:g',
          'Users',
          '/remove:g',
          'BUILTIN\Users',
        ]);

        if (result.exitCode != 0) {
          _logger.warning('icacls failed: ${result.stderr}');
        }
      } else if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
        await Process.run('chmod', ['600', filePath]);
      } else {
        _logger.warning('Unsupported platform: ${Platform.operatingSystem}');
      }
    } catch (e) {
      _logger.warning('Could not set file permissions on $filePath | $e');
    }
  }
}
