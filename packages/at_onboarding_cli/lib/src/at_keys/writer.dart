import 'dart:io';

import 'package:at_onboarding_cli/src/util/at_onboarding_exceptions.dart';
import 'package:at_onboarding_cli/src/util/home_directory_util.dart';
import 'package:at_utils/at_logger.dart';

import 'models.dart';

export 'collision_handler.dart';
export 'models.dart';

/// Atomic .atKeys file writer with secure permissions.
///
/// Three-step workflow:
/// 1. [writeToTempFile] - Creates temp file with chmod 600
/// 2. [handleTargetCollision] - Resolves conflicts via collision handler
/// 3. [moveToTargetPath] - Atomically renames temp to final destination
///
/// Use [cleanupTempFile] on errors.
class AtKeysFileWriter {
  static final AtSignLogger _logger = AtSignLogger('AtKeysFileWriter');

  /// Writes [keysContent] to a temp file with chmod 600 permissions.
  ///
  /// Temp file is created in same directory as [targetPath] or `~/.atsign/tmp`.
  /// Caller must call [handleTargetCollision] and [moveToTargetPath] next,
  /// or [cleanupTempFile] on error.
  static Future<String> writeToTempFile(String keysContent,
      String atSign, {
        String? targetPath,
      }) async {
    // Generate unique temp file in the same directory as target
    // fallback temp dir is ~/.atsign/tmp
    final dir = targetPath != null
        ? File(targetPath).parent.path
        : HomeDirectoryUtil.getDefaultTempDir();

    final tempDir = Directory(dir);
    if (!tempDir.existsSync()) {
      tempDir.createSync(recursive: true);
    }

    // Create temp file with random suffix to ensure no collision
    final timestamp = DateTime
        .now()
        .millisecondsSinceEpoch;
    final tempPath = HomeDirectoryUtil.getDefaultTempFilePath(atSign,
        uniqueId: timestamp.toString(), parentDir: tempDir.path);
    final tempFile = File(tempPath);

    await tempFile.writeAsString(keysContent);
    _logger.finer('Su keys content to temp file: $tempPath');

    await _setSecurePermissions(tempPath);

    return tempPath;
  }

  /// Checks if [targetPath] exists and invokes [collisionHandler] if needed.
  ///
  /// Returns [targetPath] if no collision, or alternative path if handler
  /// returns [AtKeysFileCollisionUseAlternative].
  /// Cleans up [tempFilePath] and throws [AtKeysFileExistsException] if handler aborts.
  static Future<String> handleTargetCollision(String tempFilePath,
      String targetPath,
      String keysContent,
      AtKeysFileCollisionHandler collisionHandler,) async {
    if (!File(targetPath).existsSync()) {
      // No collision
      return targetPath;
    }
    _logger.info('Target file exists: $targetPath. Invoking collision handler');

    // Collision detected, invoke handler
    final context = AtKeysFileCollisionContext(
      targetFilePath: targetPath,
      keysContent: keysContent,
    );

    final result = collisionHandler(context);

    if (result is AtKeysFileCollisionUseAlternative) {
      _logger.info('Using alternative path: ${result.alternativePath}');
      return result.alternativePath;
    } else if (result is AtKeysFileCollisionAbort) {
      await cleanupTempFile(tempFilePath);
      final message =
          result.customMessage ?? 'File collision: $targetPath exists';
      throw AtKeysFileExistsException(message);
    }

    // fallback
    await cleanupTempFile(tempFilePath);
    throw AtKeysFileExistsException('File collision: $targetPath exists');
  }

  /// Atomically renames [tempFilePath] to [finalPath] and sets secure permissions.
  ///
  /// On POSIX, rename is atomic. On Windows, caller must handle collision first.
  ///
  /// Cleans up [tempFilePath] on error before rethrowing.
  static Future<File> moveToTargetPath(String tempFilePath,
      String finalPath,) async {
    final tempFile = File(tempFilePath);

    if (!tempFile.existsSync()) {
      throw StateError('Temp file does not exist: $tempFilePath');
    }

    try {
      // Create parent directory if needed
      final parentDir = File(finalPath).parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }
      _logger.finer('Moving temp file to final path: $finalPath');
      final movedFile = await tempFile.rename(finalPath);
      await _setSecurePermissions(finalPath);

      return movedFile;
    } catch (e) {
      await cleanupTempFile(tempFilePath);
      rethrow;
    }
  }

  /// Deletes [tempFilePath] if it exists. Idempotent.
  ///
  /// Throws [AtOnboardingException] if deletion fails.
  static Future<void> cleanupTempFile(String tempFilePath) async {
    try {
      final tempFile = File(tempFilePath);
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
    } catch (e) {
      throw AtOnboardingException(
          'Could not delete temp file: $tempFilePath | $e');
    }
  }

  /// Sets chmod 600 (POSIX) or restrictive ACLs (Windows) on [filePath].
  static Future<void> _setSecurePermissions(String filePath) async {
    try {
      if (Platform.isWindows) {
        _logger.finer('Setting secure permissions on file: $filePath');
        final username =
            Platform.environment['USERNAME'] ?? Platform.environment['USER'];
        if (username == null) {
          throw StateError('Could not determine username');
        }

        await Process.run(
            'icacls', [filePath, '/inheritance:r', '/grant:r', '$username:F']);
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
