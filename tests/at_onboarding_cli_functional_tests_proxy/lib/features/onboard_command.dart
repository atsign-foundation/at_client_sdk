import 'dart:io';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

Future<bool> onboardAtSign(String atSign, String cramKey, String keyFile, String rootServer) async {
  print('Onboarding $atSign to generate keys...');

  String onboardCommand = 'dart run bin/activate_cli.dart -a $atSign --cramkey $cramKey --keys $keyFile --rootServer $rootServer';
  print('Executing command: $onboardCommand');
  List<String> commandParts = onboardCommand.split(' ');
  String executable = commandParts[0];
  List<String> arguments = commandParts.skip(1).toList();

  ProcessResult result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout).catchError((error) {
    print('Process timed out or failed: $error');
    return ProcessResult(0, 1, '', 'Process timed out or failed');
  });

  print('Onboard exit code: ${result.exitCode}');
  print('Onboard stdout: ${result.stdout}');
  print('Onboard stderr: ${result.stderr}');

  String keyFilePath = '$workingDirectory/$keyFile';
  File keyFileObj = File(keyFilePath);

  if (keyFileObj.existsSync()) {
    print('✓ Key file generated successfully at: $keyFilePath');
    return true;
  } else {
    print('✗ Key file not found at: $keyFilePath');
    String stderr = result.stderr.toString();
    if (stderr.contains('Found atServer address for $atSign') &&
        stderr.contains('Connected to $atSign atServer')) {
      print('✓ Proxy connectivity test passed - found and connected to atServer');
    }
    return false;
  }
}