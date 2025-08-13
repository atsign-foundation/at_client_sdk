import 'dart:io';
import 'package:at_utils/at_logger.dart';
import '../docker_utils.dart';

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<void> cleanupTestFiles(List<String> filePaths) async {
  for (String filePath in filePaths) {
    try {
      File file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
        logger.info('✓ Cleaned up test file: $filePath');
      }
    } catch (e) {
      logger.warning('⚠ Failed to cleanup file $filePath: $e');
    }
  }
}

Future<void> stopDockerServices() async {
  logger.info('Stopping Docker Compose services...');
  try {
    ProcessResult downResult = await runDockerComposeDown();
    if (downResult.exitCode == 0) {
      logger.info('✓ Docker Compose services stopped successfully');
    } else {
      logger.warning('⚠ Warning: docker compose down failed: ${downResult.stderr}');
    }
  } catch (e) {
    logger.warning('⚠ Warning: Failed to stop Docker Compose: $e');
  }
}

Future<void> cleanupAllKeyFiles() async {
  const String workingDirectory = '../../packages/at_onboarding_cli';
  Directory workingDir = Directory(workingDirectory);
  List<FileSystemEntity> files = workingDir.listSync();

  for (FileSystemEntity file in files) {
    if (file is File && file.path.endsWith('.atKeys')) {
      logger.info('Removing existing key file: ${file.path}');
      file.deleteSync();
    }
  }
}