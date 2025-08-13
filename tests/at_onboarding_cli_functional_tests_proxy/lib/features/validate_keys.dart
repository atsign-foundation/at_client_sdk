import 'dart:io';
import 'dart:convert';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

Future<bool> validateEnrollmentKeys(String atSign, String keyFile, String rootServer) async {
  print('Validating enrollment keys for $atSign...');

  String keyFilePath = '$workingDirectory/$keyFile';
  File keyFileObj = File(keyFilePath);

  if (!keyFileObj.existsSync()) {
    print('✗ Key file does not exist: $keyFilePath');
    return false;
  }

  print('✓ Key file exists: $keyFilePath');

  try {
    String keyContent = keyFileObj.readAsStringSync();
    if (keyContent.isEmpty) {
      print('✗ Key file is empty');
      return false;
    }

    Map<String, dynamic> keyData = jsonDecode(keyContent);

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

  print('Testing enrollment keys by running onboard command (should show already activated)...');
  String authCommand = 'dart run bin/activate_cli.dart onboard -a $atSign --keys $keyFile --rootServer $rootServer';
  print('Executing command: $authCommand');
  List<String> authParts = authCommand.split(' ');

  ProcessResult authResult = await Process.run(
    authParts[0],
    authParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  print('Auth test exit code: ${authResult.exitCode}');
  print('Auth test stdout: ${authResult.stdout}');
  print('Auth test stderr: ${authResult.stderr}');

  String stdout = authResult.stdout.toString();
  String stderr = authResult.stderr.toString();

  // Check for "already activated" message
  if (stdout.toLowerCase().contains('already activated') || stderr.toLowerCase().contains('already activated')) {
    print('✓ Enrollment keys validated - atSign is already activated');
    return true;
  }

  // Fallback checks for other success indicators
  if (authResult.exitCode == 0 || 
      stderr.toLowerCase().contains('authenticated') || 
      stderr.toLowerCase().contains('success') ||
      stdout.toLowerCase().contains('authenticated') ||
      stdout.toLowerCase().contains('success')) {
    print('✓ Enrollment keys validated successfully');
    return true;
  }

  print('✗ Enrollment key validation failed - expected "already activated" message');
  return false;
}