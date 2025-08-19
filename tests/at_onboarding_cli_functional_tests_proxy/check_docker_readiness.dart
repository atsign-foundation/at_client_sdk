import 'dart:io';
import 'lib/docker_utils.dart';

const List<String> requiredContainers = ['at_proxyserver', 'at_virtualenv'];
const String yesFlag = '-y';
const int maxRetries = 5;
const Duration retryDelay = Duration(seconds: 3);

Future<bool> checkDockerContainers() async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      print('Attempt $attempt of $maxRetries...');

      ProcessResult result = await Process.run('docker', ['ps']);

      if (result.exitCode != 0) {
        print('Failed to run docker ps: ${result.stderr}');
        if (attempt < maxRetries) {
          print('Retrying in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
          continue;
        }
        return false;
      }

      String output = result.stdout.toString();
      List<String> foundContainers = [];

      for (String containerName in requiredContainers) {
        if (output.contains(containerName)) {
          foundContainers.add(containerName);
        }
      }

      if (foundContainers.length == requiredContainers.length) {
        print('✓ Found all required containers: ${foundContainers.join(', ')}');
        return true;
      } else {
        List<String> missing = requiredContainers.where((name) => !foundContainers.contains(name)).toList();
        print('Missing containers: ${missing.join(', ')}');

        if (attempt < maxRetries) {
          print('Retrying in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
          continue;
        }
      }
    } catch (e) {
      print('Error checking Docker containers: $e');
      if (attempt < maxRetries) {
        print('Retrying in ${retryDelay.inSeconds} seconds...');
        await Future.delayed(retryDelay);
        continue;
      }
    }
  }

  print('✗ Failed to find all required containers after $maxRetries attempts');
  return false;
}

Future<bool> restartDockerCompose() async {
  try {
    print('Stopping Docker Compose services...');
    ProcessResult downResult = await runDockerComposeDown();

    if (downResult.exitCode != 0) {
      print('Warning: docker compose down failed: ${downResult.stderr}');
    } else {
      print('Docker Compose services stopped successfully');
    }

    print('Starting Docker Compose services...');
    ProcessResult upResult = await runDockerComposeUp();

    if (upResult.exitCode != 0) {
      print('Failed to start Docker Compose services: ${upResult.stderr}');
      return false;
    }

    print('Docker Compose services started successfully');
    print('Waiting for services to initialize...');
    await Future.delayed(Duration(seconds: 5));

    return true;
  } catch (e) {
    print('Error restarting Docker Compose: $e');
    return false;
  }
}

void main(List<String> arguments) async {
  print('Checking Docker readiness...');

  bool autoRestart = arguments.contains(yesFlag);
  bool isReady = await checkDockerContainers();

  if (isReady) {
    print('✓ Docker containers are ready');
    exit(0);
  } else {
    print('✗ Docker containers are not ready');

    bool shouldRestart = autoRestart;

    if (!autoRestart) {
      stdout.write('Attempt starting Docker Compose services? (Y/N): ');
      String? input = stdin.readLineSync();
      shouldRestart = input?.toLowerCase() == 'y' || input?.toLowerCase() == 'yes';
    }

    if (shouldRestart) {
      print('Attempting to restart Docker Compose services...');
      bool restartSuccess = await restartDockerCompose();

      if (restartSuccess) {
        print('Rechecking Docker readiness...');
        bool recheckReady = await checkDockerContainers();

        if (recheckReady) {
          print('✓ Docker containers are now ready');
          exit(0);
        } else {
          print('✗ Docker containers still not ready after restart');
          exit(1);
        }
      } else {
        print('✗ Failed to restart Docker Compose services');
        exit(1);
      }
    } else {
      print('Skipping restart attempt');
      exit(1);
    }
  }
}