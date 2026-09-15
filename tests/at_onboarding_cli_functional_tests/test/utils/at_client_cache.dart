import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'virtualenv_ports.dart';

/// The `at_activate` entrypoint, named relative to this package's root — the
/// working directory `dart test` and the CI job both use, and the one
/// `testKeysFile` assumes, so a relative `-k` resolves the same way in parent
/// and child.
const String _activateCli =
    '../../packages/at_onboarding_cli/bin/activate_cli.dart';

/// How long a CLI command may take before this helper gives up on it.
///
/// Generous, because these commands do real network work; the point is that a
/// command which never finishes names itself instead of falling silent until
/// the test's own deadline.
const Duration cliCommandTimeout = Duration(seconds: 120);

/// Evicts every cached `AtClient` so that the next one this process asks for is
/// actually built.
///
/// ⚠️ `AtClientManager.getInstance().reset()` does not do this: the static
/// `AtClientImpl.atClientInstanceMap` survives it, so a second build for an
/// atSign already built here hands back the first client — with the storage
/// path, `AtChops`, `AtKeysIo` and preference it was born with — whenever the
/// two differ in anything the key `(atSign, enrollmentId)` does not carry.
///
/// ⛔ Never call this while another service has an operation in flight: it
/// resets the shared `AtClientManager`, turning a legible refusal into a
/// silent stall.
Future<void> evictCachedAtClients() async {
  // NOTE: stopped, not dropped — a client left running keeps its claim on its
  // storage location, and the next client of the atSign is refused there.
  for (final client
      in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
    await client.stop();
  }
  AtClientImpl.atClientInstanceMap.clear();
  AtClientManager.getInstance().reset();
}

/// Runs one `at_activate` command in its own OS process and returns its exit
/// code, streaming its output as it arrives.
///
/// ⚠️ Not `auth_cli.wrappedMain`: in-process each command mints its own
/// `~/.atsign/storage/<atSign>/at_activate/<millisecondsSinceEpoch>` directory
/// while the static client cache honours only the first, so a second command
/// silently runs against the first's client and store — and a separate process
/// runs `main`, which installs the keyfile retrofit lock.
///
/// ⚠️ Streamed rather than `Process.run`, whose buffered output a child that
/// never exits takes with it; [cliCommandTimeout] bounds the wait so a stuck
/// command names itself.
///
/// ⚠️ The child logs almost nothing unless [args] carries `-v` (`info`) or
/// `--debug` (`finest`) — `auth_cli` sets `AtSignLogger.root_level` to `shout`
/// otherwise — so a silenced child reads exactly like a stalled one.
Future<int> runCliCommand(List<String> args) async {
  // NOTE: the at_activate child builds its own client and defaults to port 64.
  final rooted = _withRootPort(args);
  final proc = await Process.start(
      Platform.resolvedExecutable, ['run', _activateCli, ...rooted]);

  final out = proc.stdout.transform(utf8.decoder).listen(stdout.write);
  final err = proc.stderr.transform(utf8.decoder).listen(stderr.write);
  // NOTE: no interactive user is attached, so leaving the pipe open would
  // block on any prompt; EOF is the truthful answer to one.
  await proc.stdin.close();

  try {
    return await proc.exitCode.timeout(cliCommandTimeout);
  } on TimeoutException {
    proc.kill(ProcessSignal.sigkill);
    throw StateError(
        'at_activate ${args.isEmpty ? "(no args)" : args.first} did not exit '
        'within $cliCommandTimeout and was killed. Its output is above, and it '
        'is complete up to the moment it stopped.');
  } finally {
    await out.cancel();
    await err.cancel();
  }
}

/// [args] with the root server's port supplied where the caller gave none.
List<String> _withRootPort(List<String> args) {
  final out = [...args];
  final i = out.indexWhere((a) => a == '-r' || a == '--rootServer');
  if (i < 0) return [...out, '-r', 'vip.ve.atsign.zone:$virtualenvRootPort'];
  if (i + 1 >= out.length || out[i + 1].contains(':')) return out;
  out[i + 1] = '${out[i + 1]}:$virtualenvRootPort';
  return out;
}
