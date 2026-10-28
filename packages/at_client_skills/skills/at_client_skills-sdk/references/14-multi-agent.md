# Headless Agents & Multi-Instance Coordination

How to run `at_client` in a process with no UI — a daemon, agent, CLI tool, or
integration-test driver — and how multiple instances of the same agent
coordinate without stepping on each other.

---

## Headless auth — `CLIBase` (`at_client_cli`)

Don't hand-roll `.atKeys` loading and PKAM auth in headless Dart. `CLIBase`
does arg parsing, key loading, authentication, and client setup in one call:

```sh
dart pub add at_client_cli
```

```dart
import 'package:at_client_cli/at_client_cli.dart';

void main(List<String> args) async {
  final AtClient atClient =
      (await CLIBase.fromCommandLineArgs(args, namespace: 'my_app')).atClient;
  // ready — collections, notifications, RPC all work from here
}
```

Standard flags are provided by `CLIBase.argsParser` (`-a` atsign, `-k` path to
`.atKeys`, `-n` namespace if not fixed in code, `-s` storage directory,
verbose, etc.). This is the same pattern the canonical TUI example uses
(`packages/at_client/example/bin/collections_todos.dart`).

`CLIBase` waits for the client to come online, and otherwise stops it and
throws: `AtCredentialRefusedException` when the atServer refuses the keys,
`AtEnrollmentPendingException` when the keyfile holds only an enrollment
request, `SecondaryNotFoundException` when the atDirectory has no atServer for
the atSign, and `SecondaryServerConnectivityException` only when the atServer
is not reached in time. A retry loop catches that last one alone; the others
need a person.

## One process, one storage path

Every `at_client` process needs its **own** storage. One store is held by one
live client: a second `open` on the same location in one process is refused,
and two processes on one location corrupt it.

```dart
import 'package:at_client_cli/at_client_cli.dart';

final dir = Directory.systemTemp.createTempSync('agent_').path;
final prefs = AtClientPreference()..namespace = 'my_app';
final client = await Atsign(atSign).open(
    keys: CliKeys.fileFor(atSign, path: keysPath),
    preference: prefs,
    storage: CliKeys.storageFor(atSign, program: 'my_app', path: dir),
    lookUps: secureSocketLookUps(),
    secondaryAddressFinder:
        CacheableSecondaryAddressFinder(prefs.rootDomain, prefs.rootPort));
```

`CliKeys.storageFor` is a `HiveAtClientStorage` the client closes when it
stops. The storage object is where the store lives: at_client ignores the
deprecated `AtClientPreference.hiveStoragePath`, and at_client 4.0 removed
`commitLogPath`.

`CLIBase` handles this for typical single-instance CLIs, keeping the store
under `~/.atsign/storage/<atSign>/<namespace>/`. When launching several
instances of the same agent on one machine, generate a unique temp directory
per instance and pass it as `-s`.

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
Future<ServerMutexLease?> tryAcquire(String taskId) =>
    atClient.tryAcquireServerMutex(
        AtKey.fromString('lock.$taskId.my_app${atClient.getCurrentAtSign()}'),
        ttl: const Duration(seconds: 30));

// null: the lock's record exists, so skip the task
final lease = await tryAcquire(taskId);
if (lease != null && !lease.isSpent) {
  // do the task, checking lease.isSpent before each write
}
```

- It returns null when an immutable record already exists at the lock's key:
  another instance's lock, or one this instance took itself within the ttl. A
  mutable record there is overwritten and taken, so don't keep data under a
  lock's key. Any other failure
  (network, auth) is **thrown**, so you decide whether to go ahead without it;
  a timeout can come after the atServer stored the record, and the lock then
  stays held until its ttl runs out.
- The ttl is the only release, so a crashed winner cannot hold the lock
  forever; it must be at least a millisecond and at most 15 minutes. Do the
  task within the lease: `lease.isSpent` says when it has run out, counting
  the time elapsed since the lease was taken, so a change to the wall clock
  does not move it.
- The lock is written straight to the atServer, never to the local store, and
  the key must be a self key of the client's own atSign, used as given (no
  namespace is added).
- **atServer version.** The lock needs an atServer from p3.13.0, the first to
  parse `:nc`; an older one refuses every lock, so the call throws. The record
  stays out of the commit log, and so out of every instance's sync, from
  c3.16.3 and p3.16.5. An expired lock stops blocking at once from c3.16.2
  and p3.16.5; before that it blocks for up to about ten and a half minutes.
- If the coordination is specifically "N instances of one RPC responder", you
  don't need to write this yourself — `AtRpc.server(enableRequestMutex: true)`
  is this pattern, packaged (see [13-rpc.md](13-rpc.md)).

### Pattern 2: stateless instances with no sync

For horizontally-scaled, request/response-style agents that keep no state
across restarts, skip sync entirely: give each instance ephemeral storage and a
no-op sync service, and route all operations to the remote atServer with the
client-wide preference.

```dart
import 'package:at_client_cli/at_client_cli.dart';  // ServiceFactoryWithNoOpSyncService is NOT in at_client

final prefs = AtClientPreference()
  ..namespace = 'my_app'
  ..remoteLocalPref = RemoteLocalPref.remoteOnly;  // every op hits the atServer

final client = await Atsign(atSign).open(
  keys: CliKeys.fileFor(atSign, path: keysPath),
  preference: prefs,
  storage: CliKeys.storageFor(atSign, program: 'my_app', path: tempDir.path),
  lookUps: secureSocketLookUps(),
  secondaryAddressFinder:
      CacheableSecondaryAddressFinder(prefs.rootDomain, prefs.rootPort),
  serviceFactory: ServiceFactoryWithNoOpSyncService(),
);
// ... and `await client.stop()` when the instance is done.
```

> **Gotcha:** `ServiceFactoryWithNoOpSyncService` ships from **`at_client_cli`**
> (`package:at_client_cli/at_client_cli.dart`) — it is *not* part of
> `at_client`'s public API (the identical class inside `at_client` is
> test-only). `CLIBase`'s `--never-sync` flag opens the client with it. And it
> must be paired with `remoteLocalPref = remoteOnly` (or
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
requests. `at_client` exposes this via `atClient.enrollments`:

```dart
for (final request in await atClient.enrollments.pending()) {
  await atClient.enrollments.approve(request.enrollmentId!);   // or deny / revoke
}
atClient.enrollments.requests.listen((r) => ...);   // new requests as they arrive
final passcode = await atClient.enrollments.otp();  // what the new device quotes
```

From a terminal, `at_activate approve`, `deny`, `revoke` and `auto` do the
same.

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
