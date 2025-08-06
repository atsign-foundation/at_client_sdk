import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Queue<String> _queue = Queue<String>();
int maxRetryCount = 10;
int retryCount = 1;

void main() {
  String atsign = '@sitaram🛠';
  int atsignPort = 25017;
  String rootServer = 'vip.ve.atsign.zone';

  SecureSocket _secureSocket;

  test('checking for test environment readiness', () async {
    await Future<void>.delayed(const Duration(seconds: 10));
    _secureSocket = await secureSocketConnection(rootServer, atsignPort);
    print('connection established');
    socketListener(_secureSocket);
    String response = '';
    while (response.isEmpty || response == 'data:null\n') {
      _secureSocket.write('lookup:publickey$atsign\n');
      response = await read();
      print('waiting for signing public key response : $response');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    await _secureSocket.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<SecureSocket> secureSocketConnection(String host, int port) async {
  dynamic socket;
  while (true) {
    try {
      socket = await SecureSocket.connect(host, port);
      if (socket != null || retryCount > maxRetryCount) {
        break;
      }
    } on Exception {
      print('retrying for connection.. $retryCount');
      await Future<void>.delayed(const Duration(seconds: 5));
      retryCount++;
    }
  }
  return socket;
}

/// Socket Listener
void socketListener(SecureSocket secureSocket) {
  secureSocket.listen(_messageHandler);
}

void _messageHandler(List<int> data) {
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
  int loopCount = (maxWaitMilliSeconds / 50).round();
  for (int i = 0; i < loopCount; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    int queueLength = _queue.length;
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
