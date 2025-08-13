import 'dart:io';

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