@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// A process whose client is stopped while its work waits on an atServer that
/// never answers, not even the TLS handshake, exits on its own.
void main() {
  /// How long a process may take to exit once `main` has returned.
  const exitBound = Duration(seconds: 10);

  late ServerSocket silent;
  final held = <Socket>[];

  setUp(() async {
    silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    silent.listen(held.add);
  });

  tearDown(() async {
    for (final socket in held) {
      socket.destroy();
    }
    held.clear();
    await silent.close();
  });

  /// Runs `busy_client.dart` under [arm] and reports what it printed and
  /// whether it exited within [exitBound] of `main` returning.
  Future<({List<String> lines, int? exitCode})> run(String arm) async {
    final storage = Directory.systemTemp.createTempSync('stop_exits_');
    addTearDown(() => storage.deleteSync(recursive: true));
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'test/process_exit/busy_client.dart',
      arm,
      '${silent.port}',
      storage.path,
    ]);
    final lines = <String>[];
    final mainReturned = Completer<void>();
    void record(String line) {
      lines.add(line);
      if (line == 'MAIN_RETURNS' && !mainReturned.isCompleted) {
        mainReturned.complete();
      }
    }

    final output = [process.stdout, process.stderr]
        .map((stream) => stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(record)
            .asFuture<void>())
        .toList();
    // NOTE: the bound runs from main returning, so a process that exits
    // before printing that fails below rather than passing early.
    await Future.any([mainReturned.future, process.exitCode])
        .timeout(const Duration(minutes: 2), onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      fail('main never returned:\n${lines.join('\n')}');
    });
    int? exitCode;
    try {
      exitCode = await process.exitCode.timeout(exitBound);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await Future.wait(output);
    return (lines: lines, exitCode: exitCode);
  }

  test('a stopped client lets the process exit, and its work ends as stopped',
      () async {
    final (:lines, :exitCode) = await run('stop');
    final transcript = lines.join('\n');

    expect(lines, contains('MAIN_RETURNS'), reason: transcript);
    expect(lines.firstWhere((l) => l.startsWith('IN_FLIGHT')),
        allOf(contains('isInSync=pending'), contains('monitor=notConnected')),
        reason: 'the work has to be waiting on the silent atServer when the '
            'stop lands, or this proves nothing about ending it\n$transcript');
    expect(exitCode, 0,
        reason: 'stop() closes every connection and timer, so nothing keeps '
            'the process alive once main returns\n$transcript');
    expect(lines.firstWhere((l) => l.startsWith('AFTER_STOP')),
        contains('isInSync=failed StoppedException'),
        reason: 'the caller waiting on the atServer learns the client stopped '
            '\n$transcript');
    expect(lines.where((l) => l.contains('SEVERE') || l.contains('SHOUT')),
        isEmpty,
        reason: 'a stop the owner asked for is not an error\n$transcript');
  });

  test('a client left running keeps the process alive (control)', () async {
    final (:lines, :exitCode) = await run('leave');

    expect(lines, contains('MAIN_RETURNS'), reason: lines.join('\n'));
    expect(exitCode, isNull,
        reason: 'the same work with no stop must hold the process open, or '
            'the exit above is not evidence that stop() caused it');
  });
}
