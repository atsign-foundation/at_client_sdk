import 'dart:io';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration enrollmentTimeout = Duration(seconds: 180);

/// Submits an enrollment request using the provided OTP
Future<bool> submitEnrollmentRequest(String otp, String atSign, String deviceId, String keyFile, String rootServer, String appName, String namespaces) async {
  print('Submitting enrollment request for $atSign with device ID: $deviceId');

  String enrollCommand = 'dart run bin/activate_cli.dart enroll -s $otp -a $atSign --rootServer $rootServer -d $deviceId -n "$namespaces" --app $appName --keys $keyFile';
  List<String> enrollParts = enrollCommand.split(' ');

  // Handle the namespaces parameter which contains spaces
  List<String> processedParts = [];
  bool inQuotes = false;
  String currentPart = '';

  for (String part in enrollParts) {
    if (part.startsWith('"') && part.endsWith('"')) {
      processedParts.add(part.substring(1, part.length - 1));
    } else if (part.startsWith('"')) {
      inQuotes = true;
      currentPart = part.substring(1);
    } else if (part.endsWith('"') && inQuotes) {
      currentPart += ' $part';
      processedParts.add(currentPart.substring(0, currentPart.length - 1));
      inQuotes = false;
      currentPart = '';
    } else if (inQuotes) {
      currentPart += ' $part';
    } else {
      processedParts.add(part);
    }
  }

  print('Executing enrollment command: ${processedParts.join(' ')}');

  ProcessResult result = await Process.run(
    processedParts[0],
    processedParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(enrollmentTimeout);

  print('Enrollment command exit code: ${result.exitCode}');
  print('Enrollment command stdout: ${result.stdout}');
  print('Enrollment command stderr: ${result.stderr}');

  if (result.exitCode == 0) {
    print('✓ Enrollment request submitted successfully');
    return true;
  } else {
    String stderr = result.stderr.toString();
    String stdout = result.stdout.toString();

    // Check if the error indicates enrollment was submitted but is pending approval or waiting
    if (stderr.contains('enrollment') && (stderr.contains('pending') || stderr.contains('waiting'))) {
      print('✓ Enrollment request submitted and is pending approval');
      return true;
    }

    // Check if the enrollment was submitted but timed out waiting for approval
    if (stderr.contains('AT0023') || stderr.contains('Waited for') || stderr.contains('millis')) {
      print('✓ Enrollment request submitted but timed out waiting for approval');
      return true;
    }

    // Check if there were connection issues that might be temporary
    if (stderr.contains('unable to connect') || stderr.contains('AT0021')) {
      print('⚠ Connection issue during enrollment - may need to retry or check proxy');
      return false;
    }

    print('✗ Enrollment request failed: $stderr');
    return false;
  }
}