import 'dart:io';

import 'package:test/test.dart';

import 'check_test_env.dart';

void main() {
  String atsign = '@sitaram🛠';
  int atsignPort = 25017;
  String rootServer = 'vip.ve.atsign.zone';

  SecureSocket _secureSocket;

  test('checking for test environment readiness', () async {
    _secureSocket = await secureSocketConnection(rootServer, atsignPort);
    print('connection established');
    socketListener(_secureSocket);
    String response = '';
    print('waiting for up to 2 minutes for signing_publickey$atsign');

    // Bounded, and asserted below. Unbounded, a virtualenv that never comes up
    // spins here until the five-minute test timeout and reports that instead
    // of what was actually missing — and with no expectation after the loop, a
    // future edit letting it exit early would leave this test GREEN while the
    // environment was not ready, which is the failure this file exists to
    // prevent.
    const int maxTries = 40;
    int attempt = 0;
    while ((response.isEmpty || response == 'data:null\n') &&
        attempt < maxTries) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 3));
      attempt++;
      _secureSocket.write('lookup:signing_publickey$atsign\n');
      response = await read();
    }
    await _secureSocket.close();

    expect(response, isNotEmpty,
        reason: '$atsign never served its signing public key, so the '
            'virtualenv is not up. A test failure after this is the '
            'environment, not the product — do not read it as one.');
    expect(response, isNot('data:null\n'),
        reason: 'the atServer answered but holds no signing public key for '
            '$atsign, which the image is meant to ship');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
