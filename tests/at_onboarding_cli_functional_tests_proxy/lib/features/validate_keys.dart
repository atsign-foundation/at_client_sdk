import 'dart:io';
import 'dart:convert';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

/// Validates that enrollment keys exist and are functional
Future<bool> validateEnrollmentKeys(String atSign, String keyFile, String rootServer) async {
  print('Validating enrollment keys for $atSign...');

  // Check if key file exists
  String keyFilePath = '$workingDirectory/$keyFile';
  File keyFileObj = File(keyFilePath);

  if (!keyFileObj.existsSync()) {
    print('✗ Key file does not exist: $keyFilePath');
    return false;
  }

  print('✓ Key file exists: $keyFilePath');

  // Validate key file content
  try {
    String keyContent = keyFileObj.readAsStringSync();
    if (keyContent.isEmpty) {
      print('✗ Key file is empty');
      return false;
    }

    // Try to parse as JSON to ensure it's valid
    Map<String, dynamic> keyData = jsonDecode(keyContent);

    // Check for essential keys
    List<String> requiredKeys = ['aesPkamPublicKey', 'aesPkamPrivateKey', 'aesEncryptPublicKey', 'aesEncryptPrivateKey'];
    for (String requiredKey in requiredKeys) {
      if (!keyData.containsKey(requiredKey) || keyData[requiredKey] == null || keyData[requiredKey].toString().isEmpty) {
        print('✗ Key file missing required key: $requiredKey');
        return false;
      }
    }

    print('✓ Key file contains all required keys');

  } catch (e) {
    print('✗ Failed to parse key file: $e');
    return false;
  }

  // Test authentication with the keys
  print('Testing authentication with enrollment keys...');
  String authCommand = 'dart run bin/activate_cli.dart -a $atSign --keys $keyFile --rootServer $rootServer';
  List<String> authParts = authCommand.split(' ');

  ProcessResult authResult = await Process.run(
    authParts[0],
    authParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  print('Auth test exit code: ${authResult.exitCode}');
  print('Auth test stdout: ${authResult.stdout}');
  print('Auth test stderr: ${authResult.stderr}');

  if (authResult.exitCode != 0) {
    String stderr = authResult.stderr.toString();
    if (!stderr.toLowerCase().contains('authenticated') && !stderr.toLowerCase().contains('success')) {
      print('✗ Authentication test failed');
      return false;
    }
  }

  print('✓ Authentication test successful');
  print('✓ Enrollment key validation completed successfully');
  return true;
}