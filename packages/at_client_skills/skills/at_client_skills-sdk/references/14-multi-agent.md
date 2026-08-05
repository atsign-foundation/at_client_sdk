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

Every `at_client` process needs its **own** `hiveStoragePath` and
`commitLogPath`. Two processes sharing a hive path collide on the hive boxes
and throw.

```dart
final dir = Directory.systemTemp.createTempSync('agent_').path;
final prefs = AtClientPreference()
  ..hiveStoragePath = dir
  ..commitLogPath   = dir
  ..namespace       = 'my_app';
```

`CLIBase` handles this for typical single-instance CLIs; generate a unique temp
directory per instance when launching several instances of the same agent on
one machine.

> **Gotcha:** `exit()` does not flush buffered stdout — call
> `await stdout.flush()` first or log lines vanish when output is redirected.

---

## Coordinating multiple instances of one agent

Two patterns, chosen by whether instances keep state.

### Pattern 1 (default): immutable-mutex race

First instance to write an immutable key wins the task; the others skip it.
Requires raw `put`: collections don't expose immutable metadata, and the write
must target the server for *this one operation*
(`PutRequestOptions..useRemoteAtServer`) — a race against a local copy would
not be a race at all.

```dart
Future<bool> tryAcquire(String taskId) async {
  final mutexKey = AtKey.fromString(
      'lock.$taskId.my_app${atClient.getCurrentAtSign()}')
    ..metadata = (Metadata()
      ..immutable = true   // first writer wins
      ..ttl = 30000);      // auto-releases the lock after 30 s
  try {
    await atClient.put(mutexKey, 'lock',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);
    return true;                       // we own the task
  } catch (err) {
    // Contention has NO typed exception — the losing put() THROWS, and the
    // only reliable signal is the error text:
    if (err.toString().toLowerCase().contains('immutable')) {
      return false;                    // another instance won the race
    }
    rethrow;                           // network/auth error — not contention
  }
}
```

- The losing `put()` **throws**; it does not return false. Detect contention by
  inspecting the message, exactly as the SDK itself does
  (`AtRpc._tryAcquireSessionMutex`).
- Always set a `ttl` so a crashed winner cannot hold the lock forever. TTL
  expiry is also the release mechanism: deleting an immutable key early needs
  the protocol-level `force` flag, which `atClient.delete` does not expose.
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

final prefs = AtClientPreference()
  ..remoteLocalPref = RemoteLocalPref.remoteOnly  // every op hits the atServer
  /* ...storage paths etc... */;

await AtClientManager.getInstance().setCurrentAtSign(
  atSign, 'my_app', prefs,
  serviceFactory: ServiceFactoryWithNoOpSyncService(),
);
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
| Keep state / use collections        | 1 — immutable-mutex race per task          |
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
*infrastructure*: mutex keys (immutable metadata and per-operation remote
writes are not available through the collection API — by design; a
`remoteLocalPref = remoteOnly` client routes collection ops remote too) and
the no-sync scaling pattern.
Give such keys a distinct key-name prefix within your app's namespace (e.g.
`lock.`, as `AtRpc` does with `session_mutexes.`) so they never collide with
collection keys.
