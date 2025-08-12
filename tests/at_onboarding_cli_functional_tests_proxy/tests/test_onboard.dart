import 'dart:io';
import 'package:test/test.dart';
import '../check_docker_readiness.dart';

const String onboardCommand = 'dart run bin/activate_cli.dart onboard --rootServer proxy:vip.ve.atsign.zone:443 -a relay2 --cramkey feacb0894de2d9476e903be2164b01194dcce1490acf6d588400ef469cdd6eb1027e2baae02acd820c3a4727905f3e4866572714fe554aa2284ec8bdced0d767';
const String workingDirectory = '../../packages/at_onboarding_cli';
const int expectedExitCode = 0;

void main() {
  group('Onboarding CLI Tests', () {
    test('system readiness check', () async {
      bool isReady = await checkDockerAndRootResponse();
      expect(isReady, isTrue, reason: 'Docker containers and relay must be ready before running tests');
    });

    test('onboard command execution', () async {
      List<String> commandParts = onboardCommand.split(' ');
      String executable = commandParts[0];
      List<String> arguments = commandParts.skip(1).toList();

      ProcessResult result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );

      print('Exit code: ${result.exitCode}');
      print('Stdout: ${result.stdout}');
      print('Stderr: ${result.stderr}');

      expect(result.exitCode, equals(expectedExitCode), reason: 'Onboard command should complete successfully');
    });
  });
}