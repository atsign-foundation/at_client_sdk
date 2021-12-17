import 'dart:io';

import 'package:test/test.dart';

import 'check_test_env.dart';

var maxRetryCount = 10;
var retryCount = 1;

void main() {
  var atsign = '@sitaram🛠';
  var atsignPort = 25017;
  var rootServer = 'vip.ve.atsign.zone';

  SecureSocket _secureSocket;

  test('checking for test environment readiness', () async {
    await Future.delayed(Duration(seconds: 10));
    _secureSocket = await secureSocketConnection(rootServer, atsignPort);
    print('connection established');
    socketListener(_secureSocket);
    String response = '';
    while (response.isEmpty || response == 'data:null\n') {
      _secureSocket.write('lookup:signing_publickey$atsign\n');
      response = await read();
      print('waiting for signing public key response : $response');
      await Future.delayed(Duration(seconds: 5));
    }
    await _secureSocket.close();
  }, timeout: Timeout(Duration(minutes: 5)));
}
