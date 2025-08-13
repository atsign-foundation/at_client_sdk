import 'dart:io';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

Future<bool> approveEnrollment(String atSign, String enrollmentId, String keyFile, String rootServer) async {
  print('Approving enrollment $enrollmentId for $atSign...');

  String approveCommand = 'dart run bin/activate_cli.dart approve -a $atSign -i $enrollmentId --rootServer $rootServer --keys $keyFile';
  List<String> approveParts = approveCommand.split(' ');

  ProcessResult result = await Process.run(
    approveParts[0],
    approveParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  print('Approve command exit code: ${result.exitCode}');
  print('Approve command stdout: ${result.stdout}');
  print('Approve command stderr: ${result.stderr}');

  if (result.exitCode == 0) {
    print('✓ Enrollment approved successfully');
    return true;
  } else {
    String stderr = result.stderr.toString();
    String stdout = result.stdout.toString();

    if (stdout.toLowerCase().contains('approved') || stderr.toLowerCase().contains('approved')) {
      print('✓ Enrollment approved successfully (despite non-zero exit code)');
      return true;
    }

    print('✗ Enrollment approval failed: $stderr');
    return false;
  }
}