/// Local-only readiness probe for the e2e virtualenv. Connects to each demo
/// atSign's secondary and waits until `pkamLoad` has finished installing it,
/// i.e. PKAM auth will succeed. Base-port aware (see VIRTUALENV_BASE_PORT).
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
/// ports in the virtualenv image.
///
/// Every one is probed: `pkamLoad` installs them all at once, so one atSign
/// being ready says nothing about another, and a probe missing one surfaces
/// later as an authentication failure inside a test's setUpAll. runLocal.sh
/// also restarts `@eve🛠`'s secondary, and a restart landing mid-load severs
/// its install with nothing to retry it.
const Map<String, int> atSigns = {
  '@alice🛠': 25000,
  '@bob🛠': 25003,
  '@colin🛠': 25004,
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
      // NOTE: one queue serves every probe, so drain what the previous one
      // left behind rather than reading it as this atSign's answer.
      _queue.clear();
      final socket = await _connect(rootServer, secondaryPort,
          maxTries: 30, retryIntervalSecs: 3);
      expect(socket, isNotNull, reason: 'could not connect to $secondaryPort');
      socket!.listen(_onData);

      // NOTE: pkamLoad writes pkaminstalled last, after the PKAM key and the
      // encryption public key, so it alone says the install finished.
      print('waiting up to 3 minutes for pkaminstalled$atSign (pkamLoad)');
      var response = '';
      for (var attempt = 0; response.isEmpty && attempt < 60; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 3));
        socket.write('lookup:pkaminstalled$atSign\n');
        response = await _read();
      }
      await socket.close();
      expect(response, isNotEmpty,
          reason: 'pkaminstalled$atSign not present — pkamLoad did not '
              'finish installing $atSign');
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

/// Queues each answer without the prompt the atServer appends after it, so a
/// `data:null` answer is one [_read] can recognise.
void _onData(dynamic data) {
  var text = utf8.decode(data);
  if (text.endsWith('@') && text.contains('\n')) {
    text = text.substring(0, text.lastIndexOf('\n') + 1);
  }
  _queue.add(text);
}

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
