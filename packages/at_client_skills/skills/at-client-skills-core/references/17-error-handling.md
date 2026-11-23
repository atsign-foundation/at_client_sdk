# Error Handling

Three different families of thing get thrown, and they call for different
treatment. Working out which family you are looking at is the first step — most
bad error handling here comes from catching the wrong one.

| Family | Examples | Means | Do |
| ------ | -------- | ----- | -- |
| Dart core errors | `ArgumentError`, `StateError`, `LateInitializationError` | **Your bug** — the call was invalid | Fix the call; don't catch |
| `AtException` + subtypes | `AtKeyException`, `AtConnectException`, `AtDecryptionException` | Runtime or environmental | Catch and handle |
| Outside the `AtException` tree | `CollectionOpException`, `StoppedException`, `TimeoutException` (`dart:async`) | Real runtime conditions that `on AtException` will **not** catch | Catch explicitly |

`AtException` is the root of everything the protocol layer throws, so it is the
catch-all worth writing — but it is not sufficient on its own. `ArgumentError`
and `StateError` are not in that tree and must not be swept up with it, and the
third row is the one that surprises people: those types only implement
`Exception`, so a handler written solely as `on AtException` silently misses
them.

**No extra dependency:** `at_client` re-exports `at_commons`, so every
`AtException` type is already available from
`import 'package:at_client/at_client.dart'` — and the deprecated `at_client`
copies of `AtClientException` / `AtKeyException` are *not* exported, so the
normal import gives you the right ones. A few types are named by `at_auth`
rather than re-exported (`AtAuthenticationException` among them); they still
extend `AtException`, so `on AtException` catches them — you just cannot name
one in an `on` clause without importing `at_auth`, which an app should not
need to do.

---

## Don't catch the programming errors

`AtCollection` signals misuse with Dart's core errors, and each one means the
code is wrong rather than the environment:

| Thrown | Cause |
| ------ | ----- |
| `ArgumentError` | namespace without a `.`; `update`/`delete` on an item you don't own |
| `StateError` | `create` with an id that already exists; `delete` on an item that still has sub-items |

Wrapping these in `try`/`catch` hides a defect instead of fixing it. Use
`upsert` if you meant idempotent, `cascade: true` if you meant to remove
descendants, and check ownership before mutating.

---

## `CollectionOpException` — the partial-failure case

Every `AtCollection` write fans out across keys: the self copy plus one copy
per recipient. Those succeed and fail **independently**, so `create`, `update`,
`updateSharedWith` and `delete` throw `CollectionOpException` when any
key-level op failed — carrying the per-key breakdown rather than a single
message.

It `implements Exception` directly, so `on AtException` will not catch it.
Catch it by name, and treat it as *partially applied* rather than failed:

```dart
try {
  await todos.update(item);
} on CollectionOpException catch (e) {
  // e.results   — every key, succeeded or not
  // e.failures  — just the OpFailure entries
  for (final f in e.failures) {
    // f.atKey — which key, f.op — which operation
    // f.reason is an Object: usually the underlying AtException
    final reason = f.reason;
    _log.warning(reason is AtException
        ? '${f.atKey}: ${reason.getTraceMessage()}'
        : '${f.atKey}: $reason');
  }
}
```

`e.firstFailure` is the shortcut when one example is enough. The important
consequence is that some recipients may now hold an older copy than others —
decide explicitly whether to retry the failed keys or roll the change back.

---

## `StoppedException` — the shutdown case

`StoppedException` is the odd one in this family: it is not a failure at all.
It means the client that owned the work was deliberately stopped, so the work
could not finish. You see it in two situations:

- work that was in flight when `client.stop()` landed, and any later call on
  that client — a read or write of local storage throws it, and reading one of
  the services that is now gone throws `StateError` instead;
- any call on an `at_lookup` connection whose owner has closed it.

It `implements Exception` and, like `CollectionOpException`, is deliberately
**not** an `AtException`. That is the point of it: a handler that picks a
fallback or retries on an ordinary failure would otherwise treat an
intentional shutdown as one more thing that went wrong. Catch it by name and
let the work end quietly:

```dart
try {
  await doBackgroundWork(client);
} on StoppedException {
  return;                      // expected — the app is shutting down
} on AtException catch (e) {
  _log.warning(e.getTraceMessage());   // a real failure
}
```

Order matters: `on StoppedException` has to come before any broader `catch`,
or the broader one wins and the shutdown is logged as an error.

It needs no extra dependency — `at_commons` exports it and `at_client`
re-exports `at_commons`, so it can be named in an `on` clause straight from
`import 'package:at_client/at_client.dart'`.

---

## Log the chain, not the message

`AtException` accumulates a **chained trace** as it propagates, and `toString()`
does not show it:

```dart
@override
String toString() {
  return 'Exception: $message';   // innermost message only
}
```

`getTraceMessage()` returns the whole chain, rendered as
`Failed to <intent> caused by\n<message> caused by\n<message>`. So the reflexive
`catch (e) { _log.warning('$e'); }` discards the causal history the SDK went to
the trouble of assembling — the most useful thing you have when diagnosing a
failure from a log days later:

```dart
try {
  await atClient.get(key);
} on AtException catch (e) {
  _log.warning(e.getTraceMessage());   // not '$e'
}
```

---

## Branch on the scenario, not on message text

Every `AtException` can carry an `intent` (what was being attempted) and an
`exceptionScenario` (why it failed). Branch on those rather than matching
strings:

```dart
} on AtException catch (e) {
  switch (e.exceptionScenario) {
    case ExceptionScenario.noNetworkConnectivity:
    case ExceptionScenario.rootServerNotReachable:
    case ExceptionScenario.secondaryServerNotReachable:
      // Transient — queue the work and retry with backoff.
      break;
    case ExceptionScenario.keyNotFound:
      // Nothing to read. Often not an error at all.
      break;
    default:
      _log.severe(e.getTraceMessage());
  }
}
```

`Intent` covers `syncData`, `shareData`, `fetchData`, `notifyData`,
`encryptData`, `decryptData`, key validation and the encryption-key fetches.
`ExceptionScenario` covers the connectivity cases above plus
`invalidKeyFormed`, `invalidMetadataProvided`, `keyNotFound`,
`encryptionFailed`, `decryptionFailed`, the verb-execution failures and
`atSignDoesNotExist`.

Both are nullable — an exception constructed without them carries neither, and
an empty trace stack yields an empty `getTraceMessage()`. Handle the `null`
case rather than assuming every failure is annotated.

---

## What each operation throws

Source-documented on the API itself, so this is what to catch where:

**`atClient.put`** — `AtValueException` (bad value type), `AtKeyException`
(invalid key or metadata), `AtEncryptionException` (encryption failed),
`AtPublicKeyNotFoundException` (recipient has no encryption public key),
`SelfKeyNotFoundException`, `AtPrivateKeyNotFoundException`.

**`atClient.get`** — `AtKeyException`, `AtDecryptionException`,
`AtPublicKeyChangeException`, `SharedKeyNotFoundException`,
`SelfKeyNotFoundException`, `AtPrivateKeyNotFoundException`, and
`AtClientException` when the cloud secondary is invalid or unreachable.

**`notificationService.notify`** — `AtKeyException`, `InvalidAtSignException`
(bad `sharedWith`/`sharedBy`), and `AtClientException` for missing encryption
keys, a null `notifier` under `StrategyEnum.latest`, or a failed connection.
Also `LateInitializationError` when `NotificationParams.atKey` was never set —
a bug, not a runtime condition. `fetch(id)` throws `AtClientException` when the
atServer is unreachable or times out — see
[16-notifications.md](16-notifications.md).

**A stopped notification service** — `subscribe`, `subscribeFiltered` and
`startListening` throw `StoppedException` as their first act. `notify` does
not check up front, but its own handler only catches `AtException`, so a stop
that cuts a send short propagates out as `StoppedException` rather than
arriving as an `undelivered` result. A `NotificationResult` is therefore never
how you learn that the client was stopped.

**Opening and enrolling a client** — `AtOpenRefusedException` when the
atServer refuses the keys on their first open, `AtEnrollmentPendingException`
when the keys hold only a request still awaiting approval (resume it rather
than re-enrolling), and `AtEnrollmentException` when a request was denied.
All three extend `AtException`. A `StateError` "already live" means a client
for that atSign is open in this process — `stop()` it first. See
[15-client-lifecycle.md](15-client-lifecycle.md).

**Waiting for sync to catch up** — `waitUntilCaughtUp` can end in two ways
that are not success, and neither one is an `AtException`, so `on AtException`
catches neither:

- `TimeoutException` (`dart:async`) — the `timeout` you passed elapsed while
  sync was still behind. Sync carries on; only the wait gave up.
- `StoppedException` — the sync service stopped while you were waiting, so
  catch-up is never going to happen and waiting again would not help.

See [11-sync.md](11-sync.md).

---

## Two traps worth knowing

**`AtPublicKeyChangeException` is not retryable.** On `get` it means the
encryption public key that encrypted the value is no longer the sender's
current one — they rotated keys. Nobody can decrypt that value any more,
including them. Retrying achieves nothing; the data has to be re-shared.

**`KeyNotFoundException` rarely reaches you as itself.**
`AtExceptionManager.createException` normalises exceptions on their way to
client code: an `AtClientException` passes through unchanged, a
`KeyNotFoundException` becomes an `AtKeyNotFoundException` (because
`KeyNotFoundException` is *not* an `AtClientException` subclass), and anything
else is wrapped in `AtClientException`. So catch `AtKeyNotFoundException` for a
missing key on the client side — a handler written for `KeyNotFoundException`
may never fire.
