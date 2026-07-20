import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

var _queue = Queue();

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
    secureSocket = await secureSocketConnection(
      rootServer,
      atsignPort,
      maxTries: 20,
      retryIntervalSecs: 3,
    );

    startSocketListener(secureSocket);

    String response = '';
    print('waiting for up to 2 minutes for public:publickey$atsign');

    int attempt = 0;
    int maxAttempts = 40;
    int retryIntervalSecs = 3;
    while (response.isEmpty && attempt < maxAttempts) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: retryIntervalSecs));
      }
      attempt++;
      secureSocket.write('lookup:publickey$atsign\n');
      response = await read();
    }
    await secureSocket.close();

    expect(response, isNotEmpty);
  }, timeout: Timeout(Duration(minutes: 5)));
}

Future<SecureSocket> secureSocketConnection(
  String host,
  int port, {
  int maxTries = 20,
  int retryIntervalSecs = 3,
}) async {
  dynamic socket;
  int attempts = 0;
  while (socket == null && attempts < maxTries) {
    print('Attempting to connect to $host:$port');
    attempts++;
    try {
      socket = await SecureSocket.connect(host, port);
      print('Connected to $host:$port');
    } catch (_) {
      await Future.delayed(Duration(seconds: retryIntervalSecs));
    }
  }
  return socket;
}

/// Socket Listener
void startSocketListener(SecureSocket secureSocket) {
  secureSocket.listen(_messageHandler);
}

void _messageHandler(dynamic data) {
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
        if (result == 'data:null\n') {
          result = '';
        }
        return result;
      } else {
        //log any other response and ignore
        result = '';
      }
    }
  }
  return result;
}
