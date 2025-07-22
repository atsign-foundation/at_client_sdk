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
    print('waiting for signing public key response : $response');
    while (response.isEmpty || response == 'data:null\n') {
      _secureSocket.write('lookup:signing_publickey$atsign\n');
      response = await read();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await _secureSocket.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
