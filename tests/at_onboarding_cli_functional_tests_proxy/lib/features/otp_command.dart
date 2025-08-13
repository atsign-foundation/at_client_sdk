import 'dart:io';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

Future<String> generateOtpWithExistingKeys(String atSign, String keyFile, String rootServer) async {
  print('Generating OTP for $atSign using existing keys: $keyFile');

  String otpCommand = 'dart run bin/activate_cli.dart otp -a $atSign --rootServer $rootServer --keys $keyFile';
  print('Executing command: $otpCommand');
  List<String> otpParts = otpCommand.split(' ');

  ProcessResult result = await Process.run(
    otpParts[0],
    otpParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  print('OTP command exit code: ${result.exitCode}');
  print('OTP command stdout: ${result.stdout}');
  print('OTP command stderr: ${result.stderr}');

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
        print('✓ OTP generated successfully: $otp');
        return otp;
      }
    }
  }

  throw Exception('Failed to parse OTP from output: $output');
}