import 'dart:io';

import 'package:at_onboarding_cli/src/util/at_file_util.dart';
import 'package:at_onboarding_cli/src/util/at_onboarding_exceptions.dart';
import 'package:at_utils/at_logger.dart';

import 'collision_models.dart';

export 'collision_handlers.dart';
export 'collision_models.dart';

/// .atKeys file writer with secure permissions.
///
/// Writes keys content directly to the target file path with collision handling.
class AtKeysFileWriter {
  static final AtSignLogger _logger = AtSignLogger('AtKeysFileWriter');

  /// Writes [keysContent] directly to [targetPath] with chmod 600 permissions.
  ///
  /// If [targetPath] exists, invokes [collisionHandler] to determine behavior.
  /// Returns the final path where the file was written.
  ///
  /// This method recursively checks alternative paths for collisions,
  /// up to a limit (10 attempts) to prevent infinite loops.
  static Future<String> writeKeys(
    String keysContent,
    String targetPath,
    AtKeysFileCollisionHandler collisionHandler,
  ) async {
    String currentPath = targetPath;
    int attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      if (!File(currentPath).existsSync()) {
        // No collision, write directly
        return await _writeToFile(keysContent, currentPath);
      }

      _logger
          .info('Target file exists: $currentPath. Invoking collision handler');

      final context = AtKeysFileCollisionContext(
        targetFilePath: currentPath,
        keysContent: keysContent,
      );

      final result = await collisionHandler(context);

      if (result is AtKeysFileCollisionUseAlternative) {
        _logger.info('Using alternative path: ${result.alternativePath}');
        currentPath = result.alternativePath;
      } else if (result is AtKeysFileCollisionAbort) {
        final message =
            result.customMessage ?? 'File collision: $currentPath exists';
        throw AtKeysFileExistsException(message);
      } else {
        throw AtOnboardingException(
            'Unknown collision result type: ${result.runtimeType}');
      }
      attempts++;
    }

    // Fallback if max attempts reached
    throw AtKeysFileExistsException(
        'Too many file collisions or handler loop detected. Aborting.');
  }

  /// Writes [keysContent] to [filePath] and sets secure permissions.
  static Future<String> _writeToFile(String keysContent, String filePath) async {
    // Create parent directory if needed
    final parentDir = File(filePath).parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    final file = File(filePath);
    await file.writeAsString(keysContent);
    _logger.finer('Saved keys content to file: $filePath');

    await AtFileUtil.setSecureFilePermissions(filePath);

    return filePath;
  }
}
