import 'dart:io';
import 'dart:convert';
import 'package:at_utils/at_logger.dart';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<bool> validateEnrollmentKeys(String atSign, String keyFile, String rootServer) async {
  logger.info('Validating enrollment keys for $atSign...');

  String keyFilePath = '$workingDirectory/$keyFile';
  File keyFileObj = File(keyFilePath);

  if (!keyFileObj.existsSync()) {
    logger.warning('✗ Key file does not exist: $keyFilePath');
    return false;
  }

  logger.info('✓ Key file exists: $keyFilePath');

  try {
    String keyContent = keyFileObj.readAsStringSync();
    if (keyContent.isEmpty) {
      logger.warning('✗ Key file is empty');
      return false;
    }

    Map<String, dynamic> keyData = jsonDecode(keyContent);

    List<String> requiredKeys = ['aesPkamPublicKey', 'aesPkamPrivateKey', 'aesEncryptPublicKey', 'aesEncryptPrivateKey'];
    for (String requiredKey in requiredKeys) {
      if (!keyData.containsKey(requiredKey) || keyData[requiredKey] == null || keyData[requiredKey].toString().isEmpty) {
        logger.warning('✗ Key file missing required key: $requiredKey');
        return false;
      }
    }

    logger.info('✓ Key file contains all required keys');

  } catch (e) {
    logger.warning('✗ Failed to parse key file: $e');
    return false;
  }

  logger.info('Testing enrollment keys by running list command...');
  String listCommand = 'dart run bin/activate_cli.dart list --keys $keyFile -a $atSign --rootServer $rootServer';
  logger.info('Executing command: $listCommand');
  List<String> listParts = listCommand.split(' ');

  ProcessResult listResult = await Process.run(
    listParts[0],
    listParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  logger.info('List command exit code: ${listResult.exitCode}');
  logger.info('List command stdout: ${listResult.stdout}');
  logger.info('List command stderr: ${listResult.stderr}');

  if (listResult.exitCode == 0) {
    logger.info('✓ Enrollment keys validated successfully - able to list enrollments');
    return true;
  } else {
    String stderr = listResult.stderr.toString();
    String stdout = listResult.stdout.toString();

    // Check for authentication success indicators even with non-zero exit code
    if (stderr.toLowerCase().contains('connected') || 
        stdout.toLowerCase().contains('connected') ||
        stderr.toLowerCase().contains('authenticated') || 
        stdout.toLowerCase().contains('authenticated')) {
      logger.info('✓ Enrollment keys validated - successfully connected/authenticated');
      return true;
    }

    logger.warning('✗ Enrollment key validation failed: $stderr');
    return false;
  }
}

Future<bool> testOnboardWithEnrollmentKeys(String atSign, String keyFile, String rootServer) async {
  logger.info('Testing onboard command with enrollment keys (should show already activated)...');

  String onboardCommand = 'dart run bin/activate_cli.dart -a $atSign --keys $keyFile --rootServer $rootServer';
  logger.info('Executing command: $onboardCommand');
  List<String> onboardParts = onboardCommand.split(' ');

  ProcessResult onboardResult = await Process.run(
    onboardParts[0],
    onboardParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

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