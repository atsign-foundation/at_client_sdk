import 'dart:io';
import '../docker_utils.dart';

Future<void> cleanupTestFiles(List<String> filePaths) async {
  for (String filePath in filePaths) {
    try {
      File file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
        print('✓ Cleaned up test file: $filePath');
      }
    } catch (e) {
      print('⚠ Failed to cleanup file $filePath: $e');
    }
  }
}

Future<void> stopDockerServices() async {
  print('Stopping Docker Compose services...');
  try {
    ProcessResult downResult = await runDockerComposeDown();
    if (downResult.exitCode == 0) {
      print('✓ Docker Compose services stopped successfully');
    } else {
      print('⚠ Warning: docker compose down failed: ${downResult.stderr}');
    }
  } catch (e) {
    print('⚠ Warning: Failed to stop Docker Compose: $e');
  }
}

Future<void> cleanupAllKeyFiles() async {
  const String workingDirectory = '../../packages/at_onboarding_cli';
  Directory workingDir = Directory(workingDirectory);
  List<FileSystemEntity> files = workingDir.listSync();

  for (FileSystemEntity file in files) {
    if (file is File && file.path.endsWith('.atKeys')) {
      print('Removing existing key file: ${file.path}');
      file.deleteSync();
    }
  }
}