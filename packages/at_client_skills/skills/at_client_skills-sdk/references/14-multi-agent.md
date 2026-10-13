# Headless Agents & Multi-Instance Coordination

How to run `at_client` in a process with no UI — a daemon, agent, CLI tool, or
integration-test driver — and how multiple instances of the same agent
coordinate without stepping on each other.

---

## Headless auth — `CLIBase` (`at_cli_commons`)

Don't hand-roll `.atKeys` loading and PKAM auth in headless Dart. `CLIBase`
does arg parsing, key loading, authentication, and client setup in one call:

```sh
dart pub add at_client at_cli_commons
```

```dart
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';

void main(List<String> args) async {
  final AtClient atClient =
      (await CLIBase.fromCommandLineArgs(args, namespace: 'my_app')).atClient;
  // ready — collections, notifications, RPC all work from here
}
```

Standard flags are provided by `CLIBase.argsParser` (`-a` atsign, `-k` path to
`.atKeys`, `-n` namespace if not fixed in code, verbose, etc.). This is the
same pattern the canonical TUI example uses
(`packages/at_client/example/bin/collections_todos.dart`).

## One process, one storage path

Every `at_client` process needs its **own** storage. One store is held by one
live client: a second `open` on the same location in one process is refused,
and two processes on one location corrupt it.

```dart
import 'package:at_client/hive.dart';

final dir = Directory.systemTemp.createTempSync('agent_').path;
final prefs = AtClientPreference()..namespace = 'my_app';
final storage = HiveAtClientStorage(
    atSign: atSign, storagePath: dir, closedByClient: true);
final client = await Atsign(atSign).open(
    keys: FileAtKeysIo(filePath: (_) => keysPath),
    preference: prefs,
    storage: storage);
```

`AtClientPreference.hiveStoragePath` and `commitLogPath` are deprecated; the
storage object is where the store lives.

`CLIBase` handles this for typical single-instance CLIs; generate a unique temp
directory per instance when launching several instances of the same agent on
one machine.

> **Gotcha:** `exit()` does not flush buffered stdout — call
> `await stdout.flush()` first or log lines vanish when output is redirected.

---

## Coordinating multiple instances of one agent

Two patterns, chosen by whether instances keep state.

### Pattern 1 (default): a server mutex per task

The first instance to take a task's lock does the task; the others skip it.
`atClient.tryAcquireServerMutex` takes the lock by creating an immutable self
record on the atServer, which refuses a second create until the ttl runs out —
so exactly one instance gets a lease, however many ask at once.

```dart
Future<bool> tryAcquire(String taskId) async {
  final lease = await atClient.tryAcquireServerMutex(
      AtKey.fromString('lock.$taskId.my_app${atClient.getCurrentAtSign()}'),
      ttl: const Duration(seconds: 30));
  return lease != null; // null: another instance holds the lock
}
```

- It returns null only when another instance holds the lock. Any other failure
  (network, auth) is **thrown**, so you decide whether to go ahead without it.
- The ttl is the only release, so a crashed winner cannot hold the lock
  forever; it must be at least a millisecond and at most 15 minutes. Do the
  task within the lease (`lease.isSpent` says when it has run out).
- The lock is written straight to the atServer and records no commit, so it
  never reaches the local store or any instance's sync. The key must be a self
  key of the client's own atSign.
- If the coordination is specifically "N instances of one RPC responder", you
  don't need to write this yourself — `AtRpc.server(enableRequestMutex: true)`
  is this pattern, packaged (see [13-rpc.md](13-rpc.md)).

### Pattern 2: stateless instances with no sync

For horizontally-scaled, request/response-style agents that keep no state
across restarts, skip sync entirely: give each instance ephemeral storage and a
no-op sync service, and route all operations to the remote atServer with the
client-wide preference.

```dart
import 'package:at_cli_commons/at_cli_commons.dart';  // NOT in at_client
import 'package:at_client/hive.dart';

final prefs = AtClientPreference()
  ..namespace = 'my_app'
  ..remoteLocalPref = RemoteLocalPref.remoteOnly;  // every op hits the atServer

final client = await Atsign(atSign).open(
  keys: FileAtKeysIo(filePath: (_) => keysPath),
  preference: prefs,
  storage: HiveAtClientStorage(
      atSign: atSign, storagePath: tempDir.path, closedByClient: true),
  serviceFactory: ServiceFactoryWithNoOpSyncService(),
);
// ... and `await client.stop()` when the instance is done.
```

> **Gotcha:** `ServiceFactoryWithNoOpSyncService` ships from **`at_cli_commons`**
> (`package:at_cli_commons/at_cli_commons.dart`) — it is *not* part of
> `at_client`'s public API (the identical class inside `at_client` is
> test-only). And it must be paired with `remoteLocalPref = remoteOnly` (or
> `useRemoteAtServer` per call — see
> [12-remote-atserver.md](12-remote-atserver.md)): with sync disabled, a
> default local write would never leave the machine.

| Instances…                          | Pattern                                    |
| ----------------------------------- | ------------------------------------------ |
| Keep state / use collections        | 1 — a server mutex per task                |
| Stateless request/response workers  | 2 — no-op sync + remote ops                |
| N instances of one `AtRpc` server   | `enableRequestMutex: true` (packaged 1)    |

---

## Device enrollment from an agent (APKAM)

An always-on agent is a natural approver for new-device APKAM enrollment
requests. `at_client` exposes this via `atClient.enrollmentService`:

```dart
final requests = await atClient.enrollmentService!.fetchEnrollmentRequests();
await atClient.enrollmentService!.approve(decision);   // or deny / revoke
```

The Flutter-side enrollment flows (the requesting device) are in
[05-flutter-auth.md](05-flutter-auth.md) (Flow 4).

## AtCollection-first boundary

Collections remain the home for the agent's *data* — what it produces,
consumes, and shares. The raw-key usage in this reference is confined to
*infrastructure*: mutex keys (taken with `tryAcquireServerMutex`, since a
lock is not app data and the collection API does not take one) and the no-sync
scaling pattern.
Give such keys a distinct key-name prefix within your app's namespace (e.g.
`lock.`, as `AtRpc` does with `session_mutexes.`) so they never collide with
collection keys.
