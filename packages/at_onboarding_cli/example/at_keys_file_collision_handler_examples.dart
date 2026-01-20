import 'dart:io';

import 'package:at_onboarding_cli/at_onboarding_cli.dart';

/// This example demonstrates how to implement a custom [AtKeysFileCollisionHandler]
/// that suggests an alternative path to the user when a collision is detected.
AtKeysFileCollisionResult suggestAlternativeHandler(
    AtKeysFileCollisionContext context) {
  // Suggest an alternative path by appending a timestamp
  final suggestedPath = 
      '${context.targetFilePath}.${DateTime.now().millisecondsSinceEpoch}';

  stderr.writeln('\nFile Collision Detected!');
  stderr.writeln('Target path: ${context.targetFilePath}');
  stderr.write('Would you like to use $suggestedPath instead? (y/n): ');

  final choice = stdin.readLineSync()?.trim().toLowerCase();

  if (choice == 'y') {
    stdout.writeln('Using alternative path: $suggestedPath');
    return AtKeysFileCollisionUseAlternative(suggestedPath);
  } else {
    return AtKeysFileCollisionAbort(
      customMessage: 'User declined the suggested alternative path.',
    );
  }
}

Future<void> main() async {
  final atSign = '@alice';

  // Set up onboarding preference
  final preference = AtOnboardingPreference()
    ..namespace = 'example'
    ..atKeysFilePath = 'alice_key.atKeys'
    ..cramSecret = 'your-cram-secret-here';

  final service = AtOnboardingServiceImpl(atSign, preference);

  stdout.writeln('Starting onboarding for $atSign...');

  try {
    // Pass the custom handler to the onboard method
    await service.onboard(
      onKeysFileCollision: suggestAlternativeHandler,
    );
    stdout.writeln('Success!');
  } catch (e) {
    stderr.writeln('Error: $e');
  }
}