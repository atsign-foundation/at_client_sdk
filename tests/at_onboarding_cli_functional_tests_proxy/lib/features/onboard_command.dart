import 'dart:io';
import 'package:at_utils/at_logger.dart';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<bool> onboardAtSign(String atSign, String cramKey, String keyFile, String rootServer) async {
  logger.info('Onboarding $atSign to generate keys...');

  String onboardCommand = 'dart run bin/activate_cli.dart onboard -a $atSign --cramkey $cramKey --keys $keyFile --rootServer $rootServer';
  logger.info('Executing command: $onboardCommand');
  List<String> commandParts = onboardCommand.split(' ');
  String executable = commandParts[0];
  List<String> arguments = commandParts.skip(1).toList();

  ProcessResult result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout).catchError((error) {
    logger.warning('Process timed out or failed: $error');
    return ProcessResult(0, 1, '', 'Process timed out or failed');
  });

  logger.info('Onboard exit code: ${result.exitCode}');
  logger.info('Onboard stdout: ${result.stdout}');
  logger.info('Onboard stderr: ${result.stderr}');

  String keyFilePath = '$workingDirectory/$keyFile';
  File keyFileObj = File(keyFilePath);

  if (keyFileObj.existsSync()) {
    logger.info('✓ Key file generated successfully at: $keyFilePath');
    return true;
  } else {
    logger.warning('✗ Key file not found at: $keyFilePath');
    String stderr = result.stderr.toString();
    if (stderr.contains('Found atServer address for $atSign') &&
        stderr.contains('Connected to $atSign atServer')) {
      logger.info('✓ Proxy connectivity test passed - found and connected to atServer');
    }
    return false;
  }
}