# AtClient Lifecycle

`at_client` owns the atSign lifecycle: onboarding, login and enrollment are
verbs on `Atsign`, each handing back an `AtClient` the **app owns and stops**.
The Flutter dialogs ([05-flutter-auth.md](05-flutter-auth.md)) and `CLIBase`
([14-multi-agent.md](14-multi-agent.md)) are these verbs behind UI and
argument parsing; what follows is true of the client whichever way it was
opened.

---

## 1. The verbs

```dart
import 'package:at_client/at_client.dart';

final keys = FileAtKeysIo(filePath: (_) => '/keys/@alice_key.atKeys');
final preference = AtClientPreference()
  ..namespace = 'my_namespace'
  ..syncRegex = 'my_namespace';
final storage = HiveAtClientStorage(
    atSign: '@alice', storagePath: dir.path, closedByClient: true);

// Log in on keys the app already holds.
final client = await Atsign('@alice').open(
    keys: keys, preference: preference, storage: storage);

// Onboard a newly registered atSign with its CRAM secret; the keys it mints
// land in `keys`, and the client opens on them.
final owner = await Atsign('@alice').activate(
    cramSecret: secret, keys: keys, preference: preference);

// Enroll this app with an atSign whose keys another device holds. The
// request is filed in `keys` as pending, so a restart resumes it.
final pending = await Atsign('@alice').enroll(otp: otp, app: 'my_app',
    device: 'phone', namespaces: {'my_namespace': 'rw'}, keys: keys,
    preference: preference);
final enrolled = await pending.client(preference);   // waits for the approval
final resumed = await Atsign('@alice').resumeEnrollment(
    app: 'my_app', device: 'phone', keys: keys, preference: preference);

// Which enrollment a keys store authenticates as, without building a client.
final principal = await Atsign('@alice').authenticatesAs(keys: keys);
```

`open` also takes `lookUps:` ([section 3](#3-connections)), `serviceFactory:`
(a process that must not sync hands in `ServiceFactoryWithNoOpSyncService`
from `at_cli_commons`), `atLookUp:` (a connection the caller already holds)
and `connectBudget:` (how long the one connect attempt waits before the
client comes back offline, 5 s by default).

**What can refuse:**

| Thrown                          | When                                                                                                     | Do                                                            |
| ------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `AtOpenRefusedException`        | The first open of these keys on this device, and the atServer refused them (or the atDirectory has none) | Show the cause; nothing local to serve                        |
| `AtEnrollmentPendingException`  | The keys hold only an enrollment awaiting approval                                                       | `resumeEnrollment`                                            |
| `StateError` "already live"     | A client for this atSign as the same enrollment, or on the same storage, is live in this process         | `stop()` it first; another enrollment opens beside it         |
| `AtEnrollmentException`         | `pending.client(...)`: the request was denied                                                            | Tell the user; a new `enroll` is a new request                |

---

## 2. Storage

A client holds one `AtClientStorage`, and one store is held by one live client.

```dart
HiveAtClientStorage(atSign: '@alice', storagePath: dir.path, closedByClient: true)
```

- `closedByClient: true` — the client closes the store when it stops. This is
  what an app wants: it picks the location and has nothing to tear down.
- Omit it and the store is **borrowed**: `stop()` detaches from it and the
  caller closes it. Use this only when something else shares the store.
- With no `storage:`, a Hive store opens under the deprecated
  `preference.hiveStoragePath`. `commitLogPath` is deprecated and unread; the
  client is commit-log-free.
- **Every process, and every client, needs its own store.** Two clients on one
  Hive location is refused; two processes on one location corrupt it.
- The store also keeps the last atServer address the atDirectory answered, so
  a start that cannot reach the atDirectory still finds the atServer.

---

## 3. Connections

The third platform-supplied thing, beside the keys store and the storage
bundle: an `AtLookUpFactory` that builds **every** connection the client
opens - its own, its sync service's, its monitor's, the file stream's and
the one a retrofit re-derives on - so an application chooses the transport
once.

```dart
// TLS on TCP, the default; the config is where TLS settings now live.
lookUps: secureSocketLookUps(config: SecureSocketConfig()..pathToCerts = '/certs')

// Behind a proxy that routes on the atSign: send `from:` first on every connection.
lookUps: secureSocketLookUps(onConnect: (c) => c.sendSync('from:@alice\n'))

// A factory of your own: any AtLookUp implementation, another transport.
AtLookupMuxable mine({required atSign, required rootDomain, required authenticator,
    secondaryAddressFinder, clientConfig = const {}}) => ...;
```

- Each call names what the connection is for: the atSign, the root domain,
  the authenticator (null for a connection that never authenticates), an
  optional address finder and the client config. The factory captures how
  bytes travel.
- The Flutter dialogs (`PkamDialog.show(..., lookUps: ...)` and the others)
  and `CLIBase.fromCommandLineArgs(args, lookUps: ...)` pass it through.
  `AtOnboardingPreference.lookUps` is what the CLI uses with none: the proxy
  factory when the root domain names a proxy, TLS otherwise.
- `AtClientPreference.decryptPackets`, `pathToCerts` and `tlsKeysSavePath`
  are deprecated: the transport is the factory's to configure. The default
  factory reads them until they go.
- A test's factory reaches all of a client's connections, where a lookup
  injected through `atLookUp:` reaches only the client's own.

---

## 4. Connection state

`open` makes one bounded connect attempt and hands the client back **whatever
happened**. `client.connection` is the record:

```dart
final AtConnectionState s = client.connection.current;
s.outcome;   // AtConnectionOutcome.online | offline | refused
s.cause;     // AtConnectionCause?, null when online
s.error;     // what the attempt raised, when it did
s.isOnline; s.isOffline; s.isRefused;

client.connection.changes.listen((s) => ...);   // every change, in order, no replay
await client.connection.attempt();              // one attempt now
await client.connection.awaitOnline(budget: const Duration(seconds: 30),
    retryInterval: const Duration(seconds: 3)); // until online, refused, or budget spent
```

| Outcome   | Cause                                                             | Meaning                                                                                |
| --------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `online`  | —                                                                 | Connected and the atServer accepted the keys                                           |
| `offline` | `unattempted`                                                     | Nothing has tried yet                                                                  |
| `offline` | `unreachable`                                                     | No network, or the atDirectory / atServer did not answer; local store served           |
| `offline` | `noAtServer`                                                      | The atDirectory answered: this atSign has no atServer (not activated, or reset)        |
| `offline` | `stopped`                                                         | `stop()` ran; the last change emitted                                                  |
| `refused` | `revoked`, `unauthenticated`, `invalidEnrollment`, `enrollmentNotApproved`, `otherRefusal` | The atServer rejected the keys; revocation landing mid-life arrives here too |

Every verb the client runs on its own connection keeps the state current, so
an app rarely needs `attempt()`; it subscribes to `changes` and renders.
**Flutter:** subscribe once (in `initState`), cancel in `dispose`, and follow
the client the app switches to via `AtClientManager.listenToAtSignChange`.

---

## 5. The sync service

`client.syncService` moves data between the local store and the atServer. It
runs on its own from the moment the client is built:

- a round on every **stats notification** the atServer sends (its commit id
  moved), and every `AtClientPreference.syncIntervalMins` (default 10) as a
  fallback;
- `sync()` requests a round now; requests coalesce, so a burst of calls is one
  round;
- `isInSync()` asks the atServer fresh and answers whether the local store has
  everything the atServer has and nothing is left to push;
- `isSyncInProgress`, and `addProgressListener(SyncProgressListener)` for
  `SyncProgress` events (`inProgress`, `success`, `failure`, with
  `localCommitId`, `serverCommitId`, `keyInfoList`).

Set `AtClientPreference.syncRegex` to your namespace ([11-sync.md](11-sync.md)).
Reads are local; writes apply locally at once and push in the background, and
a write made offline pushes when the atServer is reached.

`AtClientManager.getInstance().syncService` is deprecated: the service is the
client's.

---

## 6. The notification service

`client.notificationService` is the live channel from the atServer.

```dart
final sub = client.notificationService
    .subscribe(regex: r'\.my_namespace@', shouldDecrypt: true)
    .listen((n) => handle(n));
```

- **The monitor starts on the first `subscribe()`** (or 30 s after the client
  is built if nothing subscribed), when `AtClientPreference.monitorAutoStart`
  is true (the default). With it false, call `startListening()`.
- **`subscribe()` returns before the monitor is connected.** A notification
  sent in that window reports `delivered` and is never received. Before a
  send whose receipt you rely on, wait for `listening` to be true, or for
  `currentListenerStateStream` to emit `NotificationListenerState.listening`.
- The monitor reconnects on its own after a network loss until
  `stopListening()`; `currentListenerState` says where it is.
- `send(to:, namespace:, body:, expiration:)` for fire-and-forget; `notify(...)`
  for the full `NotificationParams`. A `notify` that does not wait for the
  final status (`waitForFinalDeliveryStatus: false`) reports a failure through
  `onError`; either way, a stop ends the status poll and the result says so.
- `stopAllSubscriptions()` cancels every subscription and, by default, the
  monitor. `stop()` on the client does this for you.

---

## 7. Owning the client: current, switching, stopping

```dart
AtClientManager.getInstance().use(client);   // for code that reads .atClient
```

- `use` makes a client current and notifies `AtSignChangeListener`s. It does
  **not** stop the previous current client: an app that keeps two open and
  switches has not finished with either.
- `setCurrentAtSign` and `fromAuthSession` are deprecated: they built the
  client for the caller. Build it with a verb, then `use` it.
- `reset()` is a test hook, not a logout.

**Stopping:**

```dart
await client.stop();
```

- Stops the sync service, the notification service (and its monitor) and the
  connection, whose state ends as `offline(stopped)`; releases the storage,
  closing it when it was built with `closedByClient: true`.
- **Does not drain.** A sync round in flight is abandoned at its next step;
  what it had not pushed stays queued on the store for the next client that
  opens on it. If the writes must reach the atServer before the process ends,
  wait until `isInSync()` answers true first.
- A stopped client is not restarted. `isStopped` is true, its services are
  gone, and the atSign can be opened again at once.
- Every `open` of the same atSign and enrollment, or on the same store, while
  the client is live is refused: **stop first, then open**.

**Shutdown checklist for a process:**

1. Wait for `client.syncService.isInSync()` if pending writes matter.
2. `await client.stop()` for every client the process opened.
3. Close any storage you built without `closedByClient: true`.

---

## Canonical examples

<!-- pyml disable-num-lines 3 md013-->
- [packages/at_client/README.md](../../../../at_client/README.md) — "atSign lifecycle" and "In code: one import, four verbs"
- [packages/at_client_flutter/example/lib/walkthrough.dart](../../../../at_client_flutter/example/lib/walkthrough.dart) — the four flows, `_storage`, `_adopt`
- [packages/at_client/example/bin/](../../../../at_client/example/bin/) — CLI programs opened through `CLIBase`
