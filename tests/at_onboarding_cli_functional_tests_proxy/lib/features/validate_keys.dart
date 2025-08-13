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

  logger.info('Testing enrollment keys by running onboard command (should show already activated)...');
  String authCommand = 'dart run bin/activate_cli.dart onboard -a $atSign --keys $keyFile --rootServer $rootServer';
  logger.info('Executing command: $authCommand');
  List<String> authParts = authCommand.split(' ');

  ProcessResult authResult = await Process.run(
    authParts[0],
    authParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  logger.info('Auth test exit code: ${authResult.exitCode}');
  logger.info('Auth test stdout: ${authResult.stdout}');
  logger.info('Auth test stderr: ${authResult.stderr}');

  String stdout = authResult.stdout.toString();
  String stderr = authResult.stderr.toString();

  // Check for "already activated" message
  if (stdout.toLowerCase().contains('already activated') || stderr.toLowerCase().contains('already activated')) {
    logger.info('✓ Enrollment keys validated - atSign is already activated');
    return true;
  }

  // Fallback checks for other success indicators
  if (authResult.exitCode == 0 || 
      stderr.toLowerCase().contains('authenticated') || 
      stderr.toLowerCase().contains('success') ||
      stdout.toLowerCase().contains('authenticated') ||
      stdout.toLowerCase().contains('success')) {
    logger.info('✓ Enrollment keys validated successfully');
    return true;
  }

  logger.warning('✗ Enrollment key validation failed - expected "already activated" message');
  return false;
}