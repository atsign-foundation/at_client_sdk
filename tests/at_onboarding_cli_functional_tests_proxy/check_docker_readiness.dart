import 'dart:io';
import 'dart:convert';

const String relayHost = 'vip.ve.atsign.zone';
const int relayPort = 443;
const String relayCommand = 'relay1\n';
const String expectedResponse = 'vip.ve.atsign.zone:443';
const Duration connectionTimeout = Duration(seconds: 10);
const List<String> requiredContainers = ['at_proxyserver', 'at_virtualenv'];

Future<bool> checkDockerAndRootResponse() async {
  try {
    bool dockerReady = await checkDockerContainers();
    if (!dockerReady) {
      print('Docker check failed: No running containers found');
      return false;
    }
    
    bool relayReady = await checkForRootResponse();
    if (!relayReady) {
      print('Relay check failed: $relayHost:$relayPort not responding correctly');
      return false;
    }
    
    print('All checks passed: Docker and relay are ready');
    return true;
  } catch (e) {
    print('Error during readiness checks: $e');
    return false;
  }
}

Future<bool> checkDockerContainers() async {
  try {
    ProcessResult result = await Process.run('sudo', ['docker', 'ps']);
    
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

void main() async {
  print('Checking Docker and Relay readiness...');
  
  bool isReady = await checkDockerAndRootResponse();
  
  if (isReady) {
    print('✓ System is ready');
    exit(0);
  } else {
    print('✗ System is not ready');
    exit(1);
  }
}