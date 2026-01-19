import 'dart:io';

import 'package:chalkdart/chalk.dart';

import 'models.dart';

/// Prebuilt collision handlers
class AtKeysFileCollisionHandlers {
  /// Abort on any collision (default)
  static AtKeysFileCollisionResult abortOnCollision(
      AtKeysFileCollisionContext context) {
    return AtKeysFileCollisionAbort(
      customMessage:
          'File already exists: ${context.targetFilePath}. Use a different path.',
    );
  }

  /// Interactive handler for console applications.
  ///
  /// Prompts the user when a collision is detected on the target path.
  /// Allows users to:
  /// - Use a different path
  /// - Abort the operation
  static AtKeysFileCollisionResult interactiveConsoleHandler(
      AtKeysFileCollisionContext context) {
    stderr.writeln('');
    stderr.writeln('${chalk.red('[Error]')} File already exists!');
    stderr.writeln('File: ${context.targetFilePath}');
    stderr.writeln('');
    stderr.writeln('Options:');
    stderr.writeln('  1. Use a different path');
    stderr.writeln('  2. Abort and exit');
    stderr.write('Choose option (1-2): ');

    String? choice = stdin.readLineSync()?.trim();

    switch (choice) {
      case '1':
        stderr
            .write('${chalk.blue('[Action Required]')} Enter new file path: ');
        String? newPath = stdin.readLineSync()?.trim();
        if (newPath != null && newPath.isNotEmpty) {
          return AtKeysFileCollisionUseAlternative(newPath);
        }
        return AtKeysFileCollisionAbort(
          customMessage: 'No path provided. Aborting.',
        );
      case '2':
      default:
        return AtKeysFileCollisionAbort(
          customMessage: 'User chose to abort.',
        );
    }
  }
}
