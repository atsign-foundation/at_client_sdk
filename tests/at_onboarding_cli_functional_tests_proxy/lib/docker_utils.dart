import 'dart:io';
import 'package:at_utils/at_logger.dart';

final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

Future<ProcessResult> runDockerCompose(List<String> arguments) async {
  ProcessResult result = await Process.run('docker-compose', arguments).catchError((error) async {
    return await Process.run('docker', ['compose', ...arguments]);
  });

  if (result.exitCode != 0) {
    try {
      result = await Process.run('docker', ['compose', ...arguments]);
    } catch (e) {
      try {
        result = await Process.run('docker-compose', arguments);
      } catch (e2) {
        throw Exception('Both docker-compose and docker compose commands failed');
      }
    }
  }

  return result;
}

Future<ProcessResult> runDockerComposeDown() async {
  return await runDockerCompose(['down']);
}

Future<ProcessResult> runDockerComposeUp({bool detached = true}) async {
  List<String> args = ['up'];
  if (detached) {
    args.add('-d');
  }
  return await runDockerCompose(args);
}

Future<ProcessResult> removeDockerContainers(List<String> containerNames) async {
  return await Process.run('docker', ['rm', '-f', ...containerNames]);
}

Future<List<String>> getRunningContainers() async {
  try {
    ProcessResult result = await Process.run('docker', ['ps', '--format', '{{.Names}}']);
    if (result.exitCode == 0) {
      String output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return [];
      }
      return output.split('\n').map((name) => name.trim()).where((name) => name.isNotEmpty).toList();
    }
    return [];
  } catch (e) {
    logger.warning('Failed to get running containers: $e');
    return [];
  }
}

Future<bool> areContainersRunning(List<String> containerNames) async {
  List<String> runningContainers = await getRunningContainers();
  return containerNames.any((name) => runningContainers.contains(name));
}

Future<bool> isDockerComposeRunning() async {
  try {
    ProcessResult result = await Process.run('docker-compose', ['ps', '-q']);
    if (result.exitCode != 0) {
      // Try with docker compose
      result = await Process.run('docker', ['compose', 'ps', '-q']);
    }

    if (result.exitCode == 0) {
      String output = result.stdout.toString().trim();
      return output.isNotEmpty;
    }
    return false;
  } catch (e) {
    logger.warning('Failed to check docker compose status: $e');
    return false;
  }
}