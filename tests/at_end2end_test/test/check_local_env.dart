/// Local-only readiness probe for the e2e virtualenv. Connects to each demo
/// atSign's secondary and waits until `pkamLoad` has uploaded its public
/// key, i.e. PKAM auth will succeed. Base-port aware (see VIRTUALENV_BASE_PORT).
///
/// Run by runLocal.sh after `docker compose up` + `supervisorctl start
/// pkamLoad`. Not a real test; uses `test()` only so it runs under `dart test`
/// / `dart run` uniformly with the functional readiness scripts.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

final _queue = Queue();

/// The demo atSigns the suite authenticates as, with their legacy secondary
/// ports in the virtualenv image. `@eve🛠` is checked as well as the first one
/// because runLocal.sh reconfigures and RESTARTS its secondary: a restart that
/// landed mid-load would sever the key install with nothing to retry it, and
/// the failure would otherwise surface much later as an authentication error
/// inside a test's setUpAll.
const Map<String, int> atSigns = {
  '@alice🛠': 25000,
  '@eve🛠': 25010,
};

void main() {
  const rootServer = 'vip.ve.atsign.zone';
  final basePort =
      int.tryParse(Platform.environment['VIRTUALENV_BASE_PORT'] ?? '') ?? 64;

  for (final entry in atSigns.entries) {
    final atSign = entry.key;
    // Base-port mode shifts every secondary by (basePort + 1) - 25000; the
    // legacy (no base port) layout keeps the original 25000-based ports.
    final secondaryPort =
        basePort == 64 ? entry.value : entry.value + (basePort + 1 - 25000);

    test('e2e virtualenv readiness ($atSign @ $secondaryPort)', () async {
      // One queue serves every probe, so drain anything the previous one left
      // behind rather than reading it as this atSign's answer.
      _queue.clear();
      final socket = await _connect(rootServer, secondaryPort,
          maxTries: 30, retryIntervalSecs: 3);
      expect(socket, isNotNull, reason: 'could not connect to $secondaryPort');
      socket!.listen(_onData);

      print('waiting up to 3 minutes for publickey$atSign (pkamLoad)');
      var response = '';
      for (var attempt = 0; response.isEmpty && attempt < 60; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 3));
        socket.write('lookup:publickey$atSign\n');
        response = await _read();
      }
      await socket.close();
      expect(response, isNotEmpty,
          reason: 'publickey$atSign not present — pkamLoad did not complete');
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

Future<SecureSocket?> _connect(String host, int port,
    {int maxTries = 30, int retryIntervalSecs = 3}) async {
  SecureSocket? socket;
  for (var i = 0; socket == null && i < maxTries; i++) {
    try {
      socket = await SecureSocket.connect(host, port);
      print('connected to $host:$port');
    } catch (_) {
      await Future.delayed(Duration(seconds: retryIntervalSecs));
    }
  }
  return socket;
}

void _onData(dynamic data) => _queue.add(utf8.decode(data));

Future<String> _read({int maxWaitMs = 5000}) async {
  for (var i = 0; i < (maxWaitMs / 100).round(); i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    if (_queue.isNotEmpty) {
      final result = _queue.removeFirst().toString();
      if (result.startsWith('data:')) {
        return result == 'data:null\n' ? '' : result;
      }
    }
  }
  return '';
}
