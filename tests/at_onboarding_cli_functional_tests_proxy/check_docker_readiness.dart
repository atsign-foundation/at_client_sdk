import 'dart:convert';
import 'dart:io';
import 'lib/docker_utils.dart';

const List<String> requiredContainers = ['at_proxyserver', 'at_virtualenv'];
const String yesFlag = '-y';
const int maxRetries = 5;
const Duration retryDelay = Duration(seconds: 3);

/// Where this suite's clients connect: the proxy, which answers an atDirectory
/// lookup with its OWN address so every later connection comes back through
/// it. `cli_test.dart` passes exactly this as `proxy:vip.ve.atsign.zone:443`.
const String proxyHost = 'vip.ve.atsign.zone';
const int proxyPort = 443;

/// A pre-provisioned atSign, used only for a stateless `from:`.
///
/// **Not one of the atSigns under test.** This suite deliberately runs without
/// pkamLoad because its tests need atSigns that are NOT yet onboarded, and
/// touching one here would be the fixture consuming the very state a test is
/// about to create. `@sitaram🛠` ships in the image with a signing public key
/// already installed — which `lookup:signing_publickey` below reads, and which
/// `lookup:publickey` would not, that being state only pkamLoad creates.
const String probeAtSign = '@sitaram🛠';

const int serveMaxTries = 40;
const Duration serveRetryDelay = Duration(seconds: 3);

/// Whether the proxy can actually carry a request to a secondary and back.
///
/// ⚠️ **This is the check that was missing, and its absence is not visible in
/// a passing run.** Readiness here asked `docker ps` whether two container
/// NAMES existed and nothing more, so it returned success seconds after
/// `compose up` while the atServer inside was still starting. The suite then
/// slept a fixed ten seconds and began, and a CRAM onboard died mid-connection
/// with "The connection went away before a response arrived" — which reads as a
/// product failure rather than an environment that was never up. Measured on a
/// slower machine than CI's: every one of the four tests failed from a cold
/// start, and all four passed against the same containers once warm.
///
/// It probes the PROXY rather than the atServer directly, because the proxy is
/// the path this suite uses and it has its own upstream to bring up: a check
/// that talked to port 64 could pass while the bridge was still unusable.
Future<bool> proxyServesSecondary() async {
  for (int attempt = 1; attempt <= serveMaxTries; attempt++) {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(proxyHost, proxyPort,
          timeout: const Duration(seconds: 10));
      final responses = StringBuffer();
      final done = socket.listen((data) => responses.write(utf8.decode(data)));

      // `from:` opens the bridge to the secondary — the half a bare TCP
      // connect to the proxy does not exercise, since the proxy answers
      // anything that is not a `from:` with its own address and closes.
      socket.write('from:$probeAtSign\n');
      await Future<void>.delayed(const Duration(seconds: 2));
      // And a real read over that bridge, so "the atServer answers" is proven
      // rather than "a socket opened".
      socket.write('lookup:signing_publickey$probeAtSign\n');
      await Future<void>.delayed(const Duration(seconds: 2));

      await done.cancel();
      final text = responses.toString();
      if (text.contains('data:') && !text.contains('data:null')) {
        print('✓ the proxy carried a lookup to $probeAtSign and back');
        return true;
      }
      print('attempt $attempt of $serveMaxTries: the proxy is listening but '
          'the atServer has not answered yet');
    } catch (e) {
      print('attempt $attempt of $serveMaxTries: cannot reach the proxy at '
          '$proxyHost:$proxyPort yet ($e)');
    } finally {
      await socket?.close();
    }
    if (attempt < serveMaxTries) await Future.delayed(serveRetryDelay);
  }
  print('✗ the proxy never carried a request to $probeAtSign. The containers '
      'are up, so this is the atServer or the bridge still starting — or a '
      'proxy that cannot reach the virtualenv atDirectory. Do NOT read a test '
      'failure after this as a product failure.');
  return false;
}

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
  // Containers first: it fails in seconds with a clear message when compose
  // never came up, which the slower probe below would only report as a
  // timeout.
  bool isReady = await checkDockerContainers() && await proxyServesSecondary();

  if (isReady) {
    print('✓ Docker containers are ready and the proxy is serving');
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

        if (recheckReady && await proxyServesSecondary()) {
          print('✓ Docker containers are now ready and the proxy is serving');
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