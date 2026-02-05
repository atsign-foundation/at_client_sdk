import 'dart:io';

import 'package:chalkdart/chalk.dart';

/// Prebuilt collision handlers
class AtKeysFileCollisionHandlers {
  /// Interactive handler for console applications.
  ///
  /// Prompts the user when a collision is detected on the target path.
  /// Allows users to:
  /// - Use a different path
  /// - Abort the operation
  static AtKeysFileCollisionResult interactiveConsoleHandler(
      AtKeysFileCollisionContext context) {
    stderr.writeln('');
    stderr.writeln('${chalk.red('[Error]')} File already exists at:'
        ' ${context.targetFilePath}');
    stderr.writeln('');
    stderr.writeln('${chalk.blue('[Action Required]')} Options:');
    stderr.writeln('\t\t\t1. Use a different path');
    stderr.writeln('\t\t\t2. Abort');
    stderr.write('Choose option (1-2): ');

    String? choice = stdin.readLineSync()?.trim();

    if (choice == null) {
      return AtKeysFileCollisionAbort(
        customMessage: 'No input received. Aborting.',
      );
    }

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