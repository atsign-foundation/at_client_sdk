import 'dart:io';

import 'package:test/test.dart';

/// Where the RPC client's log lines go on a platform with a stderr.
void main() {
  group('Given a program that sets no logging handler', () {
    test(
        'when the RPC client logs, then the line goes to stderr and not to '
        'the program\'s stdout', () async {
      final run = await Process.run(Platform.resolvedExecutable,
          ['run', 'test/rpc/rpc_client_logs.dart']);

      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect('${run.stdout}', isNot(contains('rpc-client-log-probe')),
          reason: 'a program that writes its own output to stdout gets none '
              'of the RPC client\'s log lines mixed into it');
      expect('${run.stderr}', contains('rpc-client-log-probe'),
          reason: 'the control: the probe logged, and the line reached a '
              'stream this test reads');
    });
  });
}
