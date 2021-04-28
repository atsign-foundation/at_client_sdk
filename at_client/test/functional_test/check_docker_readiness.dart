import 'dart:io';

import 'package:test/test.dart';

import 'check_test_env.dart';

var maxRetryCount = 10;
var retryCount = 1;

void main() {
  var atsign = '@sitaram🛠';
  var atsign_port = 25017;
  var root_server = 'vip.ve.atsign.zone';

  SecureSocket _secureSocket;

  test('checking for test environment readiness', () async {
    await Future.delayed(Duration(seconds: 10));
    _secureSocket = await secure_socket_connection(root_server, atsign_port);
    if (_secureSocket != null) {
      print('connection established');
    }
    socket_listener(_secureSocket);
    var response;
    while (response == null || response == 'data:null\n') {
      _secureSocket.write('lookup:signing_publickey$atsign\n');
      response = await read();
      print('waiting for signing public key response : $response');
      await Future.delayed(Duration(seconds: 5));
    }
    await _secureSocket.close();
  }, timeout: Timeout(Duration(minutes: 5)));
}
