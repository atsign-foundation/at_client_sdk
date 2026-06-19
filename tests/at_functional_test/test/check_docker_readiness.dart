import 'dart:io';

import 'package:test/test.dart';

import 'check_test_env.dart' as check_utils;

var maxRetryCount = 10;
var retryCount = 1;

void main() {
  var atsign = '@sitaram🛠';
  var rootServer = 'vip.ve.atsign.zone';
  // @sitaram🛠's secondary is 25017 by default; a base-port virtualenv shifts
  // every secondary by (VIRTUALENV_BASE_PORT + 1) - 25000.
  final basePort =
      int.tryParse(Platform.environment['VIRTUALENV_BASE_PORT'] ?? '') ?? 64;
  var atsignPort = basePort == 64 ? 25017 : 25017 + (basePort + 1 - 25000);

  SecureSocket secureSocket;

  test('checking for test environment readiness', () async {
    secureSocket = await check_utils.secureSocketConnection(
      rootServer,
      atsignPort,
      maxTries: 20,
      retryIntervalSecs: 3,
    );
    print('connection established');

    check_utils.startSocketListener(secureSocket);

    String response = '';
    print('waiting for up to 2 minutes for signing_publickey$atsign');

    int attempt = 0;
    int maxTries = 40;
    int retryIntervalSecs = 3;
    while (
        response.isEmpty || response == 'data:null\n' && attempt < maxTries) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: retryIntervalSecs));
      }
      attempt++;
      secureSocket.write('lookup:signing_publickey$atsign\n');
      response = await check_utils.read();
    }
    await secureSocket.close();

    expect(response, isNotEmpty);
  }, timeout: Timeout(Duration(minutes: 5)));
}
