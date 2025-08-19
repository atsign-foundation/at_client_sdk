import 'dart:io';
import 'package:at_utils/at_logger.dart';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<String> generateOtpWithExistingKeys(String atSign, String keyFile, String rootServer) async {
  logger.info('Generating OTP for $atSign using existing keys: $keyFile');

  String otpCommand = 'dart run bin/activate_cli.dart otp -a $atSign --rootServer $rootServer --keys $keyFile';
  logger.info('Executing command: $otpCommand');
  List<String> otpParts = otpCommand.split(' ');

  ProcessResult result = await Process.run(
    otpParts[0],
    otpParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  logger.info('OTP command exit code: ${result.exitCode}');
  logger.info('OTP command stdout: ${result.stdout}');
  logger.info('OTP command stderr: ${result.stderr}');

  if (result.exitCode != 0) {
    throw Exception('Failed to generate OTP: ${result.stderr}');
  }

  String output = result.stdout.toString();

  List<RegExp> otpPatterns = [
    RegExp(r'OTP:\s*([A-Z0-9]+)', caseSensitive: false),
    RegExp(r'([A-Z0-9]{6,})', caseSensitive: false),
    RegExp(r'^([A-Z0-9]+)$', multiLine: true, caseSensitive: false),
  ];

  for (RegExp pattern in otpPatterns) {
    Match? match = pattern.firstMatch(output.trim());
    if (match != null) {
      String otp = match.group(1)!;
      if (otp.length >= 5) {
        logger.info('✓ OTP generated successfully: $otp');
        return otp;
      }
    }
  }

  throw Exception('Failed to parse OTP from output: $output');
}