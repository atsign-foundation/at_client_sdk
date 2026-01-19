import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/at_keys/keys_file_writer.dart';

/// Examples demonstrating the atomic temp-file write approach
/// with injectable collision handlers.

/// Example 1: Interactive CLI handler (matches the built-in CLI behavior)
/// Prompts user when a collision is detected on the target path.
AtKeysFileCollisionResult interactiveCliHandler(
    AtKeysFileCollisionContext context) {
  stderr.writeln('');
  stderr.writeln('⚠️  File Collision Detected!');
  stderr.writeln('Target file: ${context.targetFilePath}');
  stderr.writeln('');
  stderr.writeln('Options:');
  stderr.writeln('  1. Use a different path');
  stderr.writeln('  2. Abort');
  stderr.write('Choose (1-2): ');

  String? choice = stdin.readLineSync()?.trim();

  switch (choice) {
    case '1':
      stderr.write('Enter new file path: ');
      String? newPath = stdin.readLineSync()?.trim();
      if (newPath?.isNotEmpty ?? false) {
        return AtKeysFileCollisionUseAlternative(newPath!);
      }
      return AtKeysFileCollisionAbort(customMessage: 'No path provided');
    default:
      return AtKeysFileCollisionAbort(customMessage: 'User aborted');
  }
}

/// Example 2: Silent abort handler (safe default)
/// Aborts immediately if collision detected, good for automated systems.
AtKeysFileCollisionResult silentAbortHandler(
    AtKeysFileCollisionContext context) {
  stderr.writeln('File collision: ${context.targetFilePath} already exists');
  return AtKeysFileCollisionAbort(
    customMessage:
        'File already exists. Provide a different path in preferences.',
  );
}

/// Example 3: Automatic backup by using a different path
/// Automatically uses a timestamped path if a collision occurs.
AtKeysFileCollisionResult backupWithNewPathHandler(
    AtKeysFileCollisionContext context) {
  final backupPath =
      '${context.targetFilePath}.backup.${DateTime.now().millisecondsSinceEpoch}';
  stderr.writeln('Collision detected. Redirecting to: $backupPath');
  return AtKeysFileCollisionUseAlternative(backupPath);
}

/// Example 4: Enterprise vault integration
/// Backs up keys content to a secure vault and uses a unique local path.
AtKeysFileCollisionResult enterpriseVaultHandler(
    AtKeysFileCollisionContext context) {
  try {
    // Simulate backing up to enterprise vault
    stderr.writeln('Backing up keys content to secure vault...');
    
    final uniquePath = '${context.targetFilePath}.${DateTime.now().microsecondsSinceEpoch}';
    stderr.writeln('✓ Vault backup successful. Using local path: $uniquePath');

    return AtKeysFileCollisionUseAlternative(uniquePath);
  } catch (e) {
    stderr.writeln('✗ Vault backup failed: $e');
    return AtKeysFileCollisionAbort(
      customMessage: 'Enterprise backup failed - aborting to prevent data loss',
    );
  }
}

/// Example 5: Mobile app handler with versioned storage
/// When a collision occurs, it finds the next available versioned path.
AtKeysFileCollisionResult mobileAppHandler(AtKeysFileCollisionContext context) {
  int version = 1;
  String newPath = '${context.targetFilePath}.$version';
  while (File(newPath).existsSync()) {
    version++;
    newPath = '${context.targetFilePath}.$version';
  }
  stderr.writeln('Target path exists. Redirecting to versioned path: $newPath');
  return AtKeysFileCollisionUseAlternative(newPath);
}

/// Example 6: Using prebuilt handlers
/// Demonstrates the convenient prebuilt handlers.
Future<void> exampleWithPrebuiltHandlers() async {
  final atSign = '@alice';
  final preference = AtOnboardingPreference()
    ..namespace = 'example'
    ..atKeysFilePath = '/path/to/atkeys';

  final service = AtOnboardingServiceImpl(atSign, preference);

  // Example enrollment response for demonstration
  final enrollmentResponse =
      AtEnrollmentResponse('example-enrollment-id', EnrollmentStatus.approved)
        ..atAuthKeys = AtAuthKeys();

  // Option 1: Abort on collision (safest default)
  await service.onboard(
    onKeysFileCollision: AtKeysFileCollisionHandlers.abortOnCollision,
  );

  // Option 2: Interactive prompting (builtin CLI behavior)
  await service.enroll(
    'myapp',
    'device-123',
    'otp-code',
    {'myapp': 'rw'},
    keysFileCollisionHandler: AtKeysFileCollisionHandlers.interactiveConsoleHandler,
  );

  // Option 3: Manual key file creation
  await service.createAtKeysFile(
    enrollmentResponse,
    onKeysFileCollision: AtKeysFileCollisionHandlers.abortOnCollision,
  );
}

/// Example 7: Custom conditional handler
/// Makes decision based on collision context.
AtKeysFileCollisionResult conditionalHandler(
    AtKeysFileCollisionContext context) {
  // If we are in a temporary directory, we might allow redirecting to a new path
  if (context.targetFilePath.contains('temp')) {
    return AtKeysFileCollisionUseAlternative(
        '${context.targetFilePath}.${DateTime.now().millisecondsSinceEpoch}');
  }
  return AtKeysFileCollisionAbort(
    customMessage:
        'Production keys file exists. Use a different path or resolve manually.',
  );
}

/// Example 8: Full onboarding flow with custom handler
Future<void> exampleOnboardingFlow() async {
  const atSign = '@alice';
  final prefs = AtOnboardingPreference()
    ..namespace = 'myapp'
    ..atKeysFilePath = '/home/user/.atSign/@alice/atkeys'
    ..cramSecret = 'your-cram-secret-here'
    ..rootDomain = 'root.atsign.org';

  final service = AtOnboardingServiceImpl(atSign, prefs);

  try {
    // Onboard with custom interactive handler
    await service.onboard(
      maxRetries: 50,
      onKeysFileCollision: interactiveCliHandler,
    );
    stderr.writeln('✓ Onboarding complete!');
  } catch (e) {
    stderr.writeln('✗ Onboarding failed: $e');
  }
}

/// Example 9: Enroll with custom handler
Future<void> exampleEnrollmentFlow() async {
  const atSign = '@alice';
  final prefs = AtOnboardingPreference()
    ..namespace = 'myapp'
    ..atKeysFilePath = '/home/user/.atSign/@alice/atkeys'
    ..rootDomain = 'root.atsign.org';

  final service = AtOnboardingServiceImpl(atSign, prefs);

  try {
    // APKAM enrollment with backup-on-collision strategy
    final response = await service.enroll(
      'myapp', // appName
      'iphone-12', // deviceName
      'otp-from-cli', // otp
      {'myapp': 'rw'}, // namespaces
      keysFileCollisionHandler: backupWithNewPathHandler,
    );
    stderr.writeln('✓ Enrollment complete! ID: ${response.enrollmentId}');
  } catch (e) {
    stderr.writeln('✗ Enrollment failed: $e');
  }
}

void main() {
  stderr.writeln('=== AtKeys File Collision Handler Examples ===\n');
  stderr.writeln('This file demonstrates 9 different ways to handle');
  stderr.writeln('file collisions when creating .atKeys files:\n');
  stderr.writeln('1. interactiveCliHandler - User prompts (like CLI)');
  stderr.writeln('2. silentAbortHandler - Safe abort for automation');
  stderr.writeln('3. backupAndOverwriteHandler - Local backup strategy');
  stderr.writeln('4. enterpriseVaultHandler - Centralized vault backup');
  stderr.writeln('5. mobileAppHandler - Mobile device-specific logic');
  stderr.writeln('6. PrebuiltHandlers - Using AtKeysFileCollisionHandlers');
  stderr.writeln('7. conditionalHandler - Decision based on context');
  stderr.writeln('8. exampleOnboardingFlow - Full onboarding example');
  stderr.writeln('9. exampleEnrollmentFlow - Full enrollment example');
  stderr.writeln('\nKey Advantages:');
  stderr.writeln('✓ Atomic writes to temp file (no collision during write)');
  stderr.writeln('✓ Simple decision making (no retry loops)');
  stderr.writeln('✓ Injectable handlers for different use cases');
  stderr.writeln('✓ Safe by default (aborts if no handler provided)');
  stderr.writeln('✓ Modular and composable');
}
