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

/// Connects to [host]:[port], retrying while the virtualenv comes up.
///
/// ⚠️ **The retry bound used to be unreachable.** `retryCount > maxRetryCount`
/// was only ever evaluated after a SUCCESSFUL connect, so a host that refused
/// every attempt looped forever — the caller hung until its test timeout and
/// reported that, rather than the connection failure that actually happened.
/// The bound is now on the loop itself, and running out throws with the last
/// error attached.
Future<SecureSocket> secureSocketConnection(String host, int port) async {
  Object? lastError;
  for (retryCount = 1; retryCount <= maxRetryCount; retryCount++) {
    try {
      return await SecureSocket.connect(host, port,
          timeout: const Duration(seconds: 10));
    } catch (e, stackTrace) {
      lastError = e;
      print('retrying for connection.. $retryCount of $maxRetryCount');
      print('Error: $e');
      if (retryCount == 1) {
        print('Stack trace: $stackTrace');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
  throw StateError('could not connect to $host:$port after $maxRetryCount '
      'attempts; the virtualenv is not up. Last error: $lastError');
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
