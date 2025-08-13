import 'dart:io';
import 'dart:convert';

const String relayHost = 'vip.ve.atsign.zone';
const int relayPort = 443;
const String relayCommand = 'relay1\n';
const String expectedResponse = 'vip.ve.atsign.zone:443';
const Duration connectionTimeout = Duration(seconds: 10);
const List<String> requiredContainers = ['at_proxyserver', 'at_virtualenv'];
const String yesFlag = '-y';
const int maxRetries = 3;
const Duration baseRetryDelay = Duration(seconds: 2);

Future<bool> checkDockerAndRootResponse() async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      print('Attempt $attempt of $maxRetries...');
      
      bool dockerReady = await checkDockerContainers();
      if (!dockerReady) {
        if (attempt < maxRetries) {
          print('Docker check failed: No running containers found. Retrying in ${baseRetryDelay.inSeconds * attempt} seconds...');
          await Future.delayed(Duration(seconds: baseRetryDelay.inSeconds * attempt));
          continue;
        } else {
          print('Docker check failed: No running containers found');
          return false;
        }
      }
      
      bool relayReady = await checkForRootResponse();
      if (!relayReady) {
        if (attempt < maxRetries) {
          print('Relay check failed: $relayHost:$relayPort not responding correctly. Retrying in ${baseRetryDelay.inSeconds * attempt} seconds...');
          await Future.delayed(Duration(seconds: baseRetryDelay.inSeconds * attempt));
          continue;
        } else {
          print('Relay check failed: $relayHost:$relayPort not responding correctly');
          return false;
        }
      }
      
      print('All checks passed: Docker and relay are ready');
      return true;
    } catch (e) {
      if (attempt < maxRetries) {
        print('Error during readiness checks: $e. Retrying in ${baseRetryDelay.inSeconds * attempt} seconds...');
        await Future.delayed(Duration(seconds: baseRetryDelay.inSeconds * attempt));
        continue;
      } else {
        print('Error during readiness checks: $e');
        return false;
      }
    }
  }
  return false;
}

Future<bool> checkDockerContainers() async {
  try {
    ProcessResult result = await Process.run('docker', ['ps']);
    
    if (result.exitCode != 0) {
      print('Failed to run docker ps: ${result.stderr}');
      return false;
    }
    
    String output = result.stdout.toString();
    List<String> lines = output.split('\n');
    
    List<String> foundContainers = [];
    
    for (String line in lines) {
      for (String containerName in requiredContainers) {
        if (line.contains(containerName) && !foundContainers.contains(containerName)) {
          foundContainers.add(containerName);
        }
      }
    }
    
    if (foundContainers.length != requiredContainers.length) {
      List<String> missing = requiredContainers.where((name) => !foundContainers.contains(name)).toList();
      print('Missing required containers: ${missing.join(', ')}');
      return false;
    }
    
    print('Found all required containers: ${foundContainers.join(', ')}');
    return true;
  } catch (e) {
    print('Error checking Docker containers: $e');
    return false;
  }
}

Future<bool> checkForRootResponse() async {
  try {
    SecureSocket socket = await SecureSocket.connect(relayHost, relayPort);
    
    String response = '';
    bool responseReceived = false;
    bool connectionClosed = false;
    
    socket.listen(
      (data) {
        response += utf8.decode(data);
        responseReceived = true;
      },
      onDone: () {
        connectionClosed = true;
      }
    );
    
    await Future.delayed(Duration(milliseconds: 100));
    
    socket.add(utf8.encode(relayCommand));
    await socket.flush();
    
    int waitTime = 0;
    while (!connectionClosed && waitTime < 5000) {
      await Future.delayed(Duration(milliseconds: 100));
      waitTime += 100;
      if (response.contains(expectedResponse)) {
        break;
      }
    }
    
    if (!connectionClosed) {
      await socket.close();
    }
    
    if (response.trim().contains(expectedResponse)) {
      print('Relay responded correctly: ${response.trim()}');
      return true;
    } else {
      print('Relay response incorrect or empty. Expected: $expectedResponse, Got: ${response.trim()}');
      return false;
    }
  } catch (e) {
    print('Error checking relay connectivity: $e');
    return false;
  }
}

Future<bool> restartDockerCompose() async {
  try {
    print('Stopping Docker Compose services...');
    ProcessResult downResult = await Process.run('docker-compose', ['down']);
    
    if (downResult.exitCode != 0) {
      print('Warning: docker-compose down failed: ${downResult.stderr}');
    } else {
      print('Docker Compose services stopped successfully');
    }
    
    print('Starting Docker Compose services...');
    ProcessResult upResult = await Process.run('docker-compose', ['up', '-d']);
    
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
  print('Checking Docker and Relay readiness...');
  
  bool autoRestart = arguments.contains(yesFlag);
  bool isReady = await checkDockerAndRootResponse();
  
  if (isReady) {
    print('✓ System is ready');
    exit(0);
  } else {
    print('✗ System is not ready');
    
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
        print('Rechecking system readiness...');
        bool recheckReady = await checkDockerAndRootResponse();
        
        if (recheckReady) {
          print('✓ System is now ready');
          exit(0);
        } else {
          print('✗ System still not ready after restart');
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