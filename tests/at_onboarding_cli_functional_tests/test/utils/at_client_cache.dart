import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';

/// The `at_activate` entrypoint, named relative to this package's root.
///
/// That root is the working directory `dart test` and the CI job both use, and
/// it is the same assumption `testKeysFile` makes about the key paths it hands
/// out, so a relative `-k` resolves the same way in parent and child.
const String _activateCli =
    '../../packages/at_onboarding_cli/bin/activate_cli.dart';

/// How long a CLI command may take before this helper gives up on it.
///
/// Generous, because these commands do real network work against a live
/// atServer. The point is not to be tight — it is that a command which never
/// finishes must produce a message naming itself, rather than silence until the
/// test's own deadline.
const Duration cliCommandTimeout = Duration(seconds: 120);

/// Evicts every cached `AtClient` so that the next one this process asks for is
/// actually built.
///
/// ⚠️ **`AtClientManager.getInstance().reset()` does not do this, and reads as
/// though it does.** It nulls the manager's current client and drops its change
/// listeners, but `AtClientImpl.atClientInstanceMap` is **static** and survives
/// it. So the next `setCurrentAtSign` for an atSign this process has already
/// built hands back the ORIGINAL client — with the storage path, `AtChops`,
/// `AtKeysIo` and preference it was born with, whatever the caller just passed.
///
/// **When a test needs this.** Any time this process builds a client for one
/// atSign more than once and the second build differs in something the cache
/// key does not carry — and the key is only `(atSign, enrollmentId)`. That
/// means clients the TEST builds directly: every method of
/// `EnrollmentOperations` is one. CLI commands are not among them, because
/// [runCliCommand] runs those in their own process.
///
/// ⛔ **Never call this while another service has an operation in flight.** It
/// resets the shared `AtClientManager`. Evict *between* operations, never
/// inside one — and prefer not to need it at all.
void evictCachedAtClients() {
  AtClientImpl.atClientInstanceMap.clear();
  AtClientManager.getInstance().reset();
}

/// Runs one `at_activate` command in its own OS process and returns its exit
/// code, streaming its output as it arrives.
///
/// ⚠️ **Do not call `auth_cli.wrappedMain` from a test instead.** In-process,
/// every command reaches `createAtClient`, which mints
/// `~/.atsign/storage/<atSign>/at_activate/<millisecondsSinceEpoch>` — a new
/// directory on **every call**. Two commands in one process therefore always
/// name two paths for one atSign, and the client cache, keyed only by
/// `(atSign, enrollmentId)`, can honour just the first. The second silently ran
/// against the first command's client and store, and the unique path it asked
/// for was never created. That is not hypothetical: this file's tests were
/// green for exactly that reason, asserting through clients they had not built.
///
/// Evicting the cache before each command is **not** the fix. It resets the
/// shared `AtClientManager`, and doing that between a service's own operations
/// converts a legible refusal into a silent stall — measured, six minutes of it.
///
/// A separate process has neither problem, and it is what a CLI invocation
/// *is*: its own static state, its own manager, its own storage. Note it runs
/// `main`, not `wrappedMain`, so it also gets the keyfile retrofit lock that
/// `main` installs — which is the shipped behaviour and the whole point.
///
/// **Output is streamed, not buffered.** `Process.run` collects output and
/// hands it over only when the child exits, so a child that never exits takes
/// its entire log with it — which is precisely what made an earlier hang here
/// undiagnosable. And [cliCommandTimeout] bounds the wait so a stuck command
/// names itself instead of consuming the test's whole deadline in silence.
Future<int> runCliCommand(List<String> args) async {
  final proc = await Process.start(
      Platform.resolvedExecutable, ['run', _activateCli, ...args]);

  final out = proc.stdout.transform(utf8.decoder).listen(stdout.write);
  final err = proc.stderr.transform(utf8.decoder).listen(stderr.write);
  // No interactive user is attached. EOF is the truthful answer to any prompt,
  // and leaving the pipe open instead would just block on one.
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
