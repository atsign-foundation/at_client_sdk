import 'dart:io';
import 'package:at_utils/at_logger.dart';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 30);

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<bool> testOnboardOnAlreadyActivatedAtSign(String atSign, String rootServer) async {
  logger.info('Testing onboard on already activated atSign (should show already activated)...');

  String onboardCommand = 'dart run bin/activate_cli.dart onboard -a $atSign --rootServer $rootServer --cramkey dummy';
  logger.info('Executing command: $onboardCommand');
  List<String> onboardParts = onboardCommand.split(' ');

  ProcessResult onboardResult = await Process.run(
    onboardParts[0],
    onboardParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout).catchError((error) {
    if (error.toString().contains('TimeoutException')) {
      logger.warning('Command timed out - likely waiting for CRAM key input');
      return ProcessResult(0, 1, '', 'Command timed out waiting for input');
    }
    throw error;
  });

  logger.info('Onboard test exit code: ${onboardResult.exitCode}');
  logger.info('Onboard test stdout: ${onboardResult.stdout}');
  logger.info('Onboard test stderr: ${onboardResult.stderr}');

  String stdout = onboardResult.stdout.toString();
  String stderr = onboardResult.stderr.toString();

  // Check for "already activated" message
  if (stdout.toLowerCase().contains('already activated') || stderr.toLowerCase().contains('already activated')) {
    logger.info('✓ Onboard test passed - atSign is already activated');
    return true;
  }

  // Fallback checks for other success indicators
  if (onboardResult.exitCode == 0 || 
      stderr.toLowerCase().contains('authenticated') || 
      stderr.toLowerCase().contains('success') ||
      stdout.toLowerCase().contains('authenticated') ||
      stdout.toLowerCase().contains('success')) {
    logger.info('✓ Onboard test passed with success indicators');
    return true;
  }

  logger.warning('✗ Onboard test failed - expected "already activated" message');
  return false;
}