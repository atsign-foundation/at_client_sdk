import 'dart:io';
import 'package:at_utils/at_logger.dart';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<bool> approveEnrollment(String atSign, String enrollmentId, String keyFile, String rootServer) async {
  logger.info('Approving enrollment $enrollmentId for $atSign...');

  String approveCommand = 'dart run bin/activate_cli.dart approve -a $atSign -i $enrollmentId --rootServer $rootServer --keys $keyFile';
  logger.info('Executing command: $approveCommand');
  List<String> approveParts = approveCommand.split(' ');

  ProcessResult result = await Process.run(
    approveParts[0],
    approveParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  logger.info('Approve command exit code: ${result.exitCode}');
  logger.info('Approve command stdout: ${result.stdout}');
  logger.info('Approve command stderr: ${result.stderr}');

  if (result.exitCode == 0) {
    logger.info('✓ Enrollment approved successfully');
    return true;
  } else {
    String stderr = result.stderr.toString();
    String stdout = result.stdout.toString();

    if (stdout.toLowerCase().contains('approved') || stderr.toLowerCase().contains('approved')) {
      logger.info('✓ Enrollment approved successfully (despite non-zero exit code)');
      return true;
    }

    logger.warning('✗ Enrollment approval failed: $stderr');
    return false;
  }
}