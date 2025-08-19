import 'dart:io';
import 'package:at_utils/at_logger.dart';

const String workingDirectory = '../../packages/at_onboarding_cli';
const Duration commandTimeout = Duration(seconds: 120);

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<List<String>> listPendingEnrollments(String atSign, String rootServer, {String? keyFile}) async {
  logger.info('Listing pending enrollments for $atSign...');

  String listCommand;
  if (keyFile != null) {
    listCommand = 'dart run bin/activate_cli.dart list -s pending -a $atSign --rootServer $rootServer --keys $keyFile';
  } else {
    listCommand = 'dart run bin/activate_cli.dart list -s pending -a $atSign --rootServer $rootServer';
  }
  logger.info('Executing command: $listCommand');
  List<String> listParts = listCommand.split(' ');

  ProcessResult result = await Process.run(
    listParts[0],
    listParts.skip(1).toList(),
    workingDirectory: workingDirectory,
  ).timeout(commandTimeout);

  logger.info('List command exit code: ${result.exitCode}');
  logger.info('List command stdout: ${result.stdout}');
  logger.info('List command stderr: ${result.stderr}');

  if (result.exitCode != 0) {
    throw Exception('Failed to list pending enrollments: ${result.stderr}');
  }

  String output = result.stdout.toString();
  List<String> enrollmentIds = [];

  RegExp idRegex = RegExp(r'(?:ID|id|enrollmentId):\s*([a-f0-9\-]+)', caseSensitive: false);
  Iterable<Match> matches = idRegex.allMatches(output);

  for (Match match in matches) {
    String enrollmentId = match.group(1)!;
    enrollmentIds.add(enrollmentId);
  }

  if (enrollmentIds.isEmpty) {
    RegExp uuidRegex = RegExp(r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', caseSensitive: false);
    Iterable<Match> uuidMatches = uuidRegex.allMatches(output);

    for (Match match in uuidMatches) {
      enrollmentIds.add(match.group(0)!);
    }
  }

  logger.info('Found ${enrollmentIds.length} pending enrollment(s): ${enrollmentIds.join(', ')}');
  return enrollmentIds;
}