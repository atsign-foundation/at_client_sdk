import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

var _queue = Queue();
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
      _secureSocket.write('lookup:publickey$atsign\n');
      response = await read();
      print('waiting for signing public key response : $response');
      await Future.delayed(Duration(seconds: 5));
    }
    await _secureSocket.close();
  }, timeout: Timeout(Duration(minutes: 5)));
}

Future<SecureSocket> secureSocketConnection(host, port) async {
  dynamic socket;
  while (true) {
    try {
      socket = await SecureSocket.connect(host, port);
      if (socket != null || retryCount > maxRetryCount) {
        break;
      }
    } on Exception {
      print('retrying for connection.. $retryCount');
      await Future.delayed(Duration(seconds: 5));
      retryCount++;
    }
  }
  return socket;
}

/// Socket Listener
void socketListener(SecureSocket secureSocket) {
  secureSocket.listen(_messageHandler);
}

void _messageHandler(data) {
  if (data.length == 1 && data.first == 64) {
    return;
  }
  //ignore prompt(@ or @<atSign>@) after '\n'. byte code for \n is 10
  if (data.last == 64 && data.contains(10)) {
    data = data.sublist(0, data.lastIndexOf(10) + 1);
    _queue.add(utf8.decode(data));
  } else if (data.length > 1 && data.first == 64 && data.last == 64) {
    // pol responses do not end with '\n'. Add \n for buffer completion
    _queue.add(utf8.decode(data));
  } else {
    _queue.add(utf8.decode(data));
  }
}

Future<String> read({int maxWaitMilliSeconds = 5000}) async {
  String result = '';
  //wait maxWaitMilliSeconds seconds for response from remote socket
  var loopCount = (maxWaitMilliSeconds / 50).round();
  for (var i = 0; i < loopCount; i++) {
    await Future.delayed(Duration(milliseconds: 100));
    var queueLength = _queue.length;
    if (queueLength > 0) {
      result = _queue.removeFirst();
      // result from another secondary is either data or a @<atSign>@ denoting complete
      // of the handshake
      if (result.startsWith('data:') ||
          (result.startsWith('@') && result.endsWith('@'))) {
        return result;
      } else {
        //log any other response and ignore
        result = '';
      }
    }
  }
  return result;
}
