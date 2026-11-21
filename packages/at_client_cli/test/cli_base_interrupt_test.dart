@TestOn('!windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

/// A program built on CLIBase, interrupted while it waits for the approval of
/// the enrollment its keyfile holds the request for.
///
/// Catalogue: features/at_client_cli/cli_base_open.feature
///
/// The program is `fixtures/waits_for_approval.dart`, run in its own process
/// so that Ctrl-C reaches it as the user's would; its atDirectory is a
/// loopback port nothing listens on, so its wait never ends by itself.
void main() {
  late Directory dir;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() => dir = Directory.systemTemp.createTempSync('cli_interrupt_'));

  tearDown(() => dir.deleteSync(recursive: true));

  test('Ctrl-C ends the wait, keeping the request', () async {
    final keysPath = '${dir.path}/keys/key.atKeys';
    final port = await refusedPort();
    await fileRequest(
        keysPath: keysPath, rootPort: port, namespace: 'cli_test');
    expect(await pendingIn(keysPath, approvingAtSign), [approvedEnrollmentId],
        reason: 'the precondition: the keyfile holds only the request');

    final program = await Process.start(Platform.resolvedExecutable, [
      'run',
      'test/fixtures/waits_for_approval.dart',
      '-a', approvingAtSign, //
      '-k', keysPath,
      '-s', '${dir.path}/storage',
      '-r', '127.0.0.1:$port',
      '--never-sync',
    ]);
    final said = StringBuffer();
    final waiting = Completer<void>();
    program.stderr.transform(utf8.decoder).listen((text) {
      said.write(text);
      if (!waiting.isCompleted &&
          said.toString().contains(
              'Waiting for approval of enrollment $approvedEnrollmentId')) {
        waiting.complete();
      }
    });
    unawaited(program.stdout.drain<void>());
    try {
      await waiting.future.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      program.kill(ProcessSignal.sigkill);
      fail('the program never said it was waiting: $said');
    }

    var exited = false;
    unawaited(program.exitCode.then((_) => exited = true));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(exited, isFalse, reason: 'it is still waiting when Ctrl-C comes');

    program.kill(ProcessSignal.sigint);
    final exitCode =
        await program.exitCode.timeout(const Duration(seconds: 30));

    expect(await pendingIn(keysPath, approvingAtSign), [approvedEnrollmentId],
        reason: 'the request is kept for the next run');
    expect(exitCode, -ProcessSignal.sigint.signalNumber,
        reason: 'Ctrl-C ended it, and nothing else did');
  });
}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}
