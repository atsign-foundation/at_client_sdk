# Sync & Sync Lifecycle

`AtCollection<T>` reads are **local-only**; every write and every cross-atsign
delivery (shares, updates, read receipts, `watch()` re-emits) depends on
`SyncService`. Two things a real app must get right: **scope sync to your
namespace**, and understand the **asynchronous lifecycle**.

---

## 1. Scope sync to your namespace (`syncRegex`) — required

By default `AtClientPreference.syncRegex` is `null`, which means sync covers the
atsign's **entire** keystore — including keys left over from other apps and
namespaces on the same atsign. On any atsign that has been used by more than one
app, a single dangling/undeletable key from an unrelated namespace aborts the
whole sync round with:

```text
key not found : <key> does not exist in keystore
```

That **silently wedges sync for your app too**: `SyncService` stays
`SyncStatus.inProgress` indefinitely, new items never push and shared items
never arrive — so creates, updates, shares, and read receipts all fail to
propagate, and any real-time features appear broken.

**Fix:** scope sync to your app's namespace.

```dart
final acp = AtClientPreference()
  ..namespace = 'my_namespace'
  ..syncRegex = 'my_namespace';   // scope sync to THIS app's keys
```

(Where the store lives is the `storage:` the client is opened on — see
[15-client-lifecycle.md](15-client-lifecycle.md).)

The atServer always syncs a small set regardless of the regex: `shared_key`
reserved keys, the encryption public key, and namespace-less `public:` keys.
The regex match is also an unanchored substring test, so your own namespace's
`cached:` copies match it anyway. Scoping therefore does **not** break sharing
or decryption — it only excludes other apps' unrelated keys.

---

## 2. The lifecycle

- **Reads are local-only.** A collection read hits the synced Hive cache, never
  the network. A stale or empty read means sync hasn't caught up yet — not that
  the data is missing.
- **Writes apply locally immediately, then sync in the background.** The write
  returns as soon as it's in the local commit log; `SyncService` pushes it to
  the atServer afterward.
- **Fallback cadence: `AtClientPreference.syncIntervalMins` (default 10).** This
  periodic full-sync reconciles a *missed* live notification (the app was
  backgrounded, the monitor was reconnecting, or the recipient was offline when
  the change was made). Lower it (e.g. `1`) so a change made on another device
  or atsign still surfaces within a minute even when the live push didn't land.

---

## 3. Observe completion with `SyncProgressListener`

Tests and headless drivers must wait until synced before asserting. Use
`SyncProgressListener` — **not** the deprecated `sync(onDone:)`:

```dart
class _SyncedListener implements SyncProgressListener {
  final void Function() onSynced;
  _SyncedListener(this.onSynced);
  @override
  void onSyncProgressEvent(SyncProgress p) {
    if (p.stopped) return;   // shutdown, not a failure — see below
    if (p.syncStatus == SyncStatus.success) onSynced();
  }
}

final sync = client.syncService;   // the client's own; the manager's getter is deprecated
final listener = _SyncedListener(() => print('synced'));
sync.addProgressListener(listener);
// ... later:
sync.removeProgressListener(listener);
```

`SyncProgress` carries `syncStatus` (`SyncStatus`:
`started` / `notStarted` / `inProgress` / `success` / `failure`),
`localCommitId`, `serverCommitId`, `pendingPushCount`, `atClientException`,
and `stopped`.

**Check `stopped` before treating an event as a failure.** A sync service that
is stopping sends every listener one final event with `stopped` true, and
nothing follows it. That event is built with `syncStatus` set to
`SyncStatus.failure` and an `atClientException` reading "SyncService has been
stopped" — so a listener that branches on `syncStatus` alone reports a
deliberate shutdown as an error, and one waiting for `SyncStatus.success`
waits for an event that is never coming. `stopped` is what tells the two
apart, which is why the listener above returns on it first.

---

## 4. Wait for sync to settle with `waitUntilCaughtUp`

When the requirement is "don't do X until sync has settled", do **not** poll
`isSyncInProgress` or `isInSync()`. Both are point-in-time reads, so acting on
one is a check-then-act race: the answer can change between the check and the
next line, and neither tells you *when* it becomes true.

`waitUntilCaughtUp` is the primitive for this. It is an extension on
`SyncService`, so it is available on any `SyncService` reference with no cast,
no opt-in, and no change to third-party implementers:

```dart
final sync = client.syncService;   // the client's own; the manager's getter is deprecated

// Always bound the wait — see below.
await sync.waitUntilCaughtUp(timeout: const Duration(seconds: 30));
```

You do not need to call `sync()` first — it triggers an iteration itself, so a
progress event is guaranteed even when nothing else is driving sync. If local
is already caught up, the future completes immediately.

**It answers a snapshot question.** The future completes once `localCommitId`
reaches the server commit id **as it stood when you called** — remote changes
arriving afterwards do not extend the wait. So it means "I have what the server
had when I asked", not "the world is now quiet". Completion also requires the
local push queue to be empty (`pendingPushCount`), because commit-id equality
alone is not enough: writes queued after a round started have not been pushed
by the round you are watching.

**Always pass `timeout`.** It is nullable with no default, and transient
failures while waiting are deliberately tolerated — a `SyncStatus.failure`
event does *not* reject the future. The timeout is therefore the only bound
you get, and without one a stalled sync (network loss, wedged sync) hangs
forever:

```dart
try {
  await sync.waitUntilCaughtUp(timeout: const Duration(seconds: 30));
} on TimeoutException {
  // dart:async — the wait gave up; sync itself carries on.
} on StoppedException {
  // at_commons — the sync service stopped, so catch-up is not coming.
}
```

Neither is an `AtException`, so `on AtException` catches neither — see
[17-error-handling.md](17-error-handling.md). They also call for different
responses: after a `TimeoutException` the work is still in progress and
waiting longer may be reasonable, while after a `StoppedException` there is
nothing left to wait for.

For progress UI, `onProgress` fires on every `SyncProgress` event observed
while waiting, including the per-batch `inProgress` events, and runs before the
completion check so you see the same final event the future completes on.
Exceptions it throws are swallowed and logged, so a broken callback cannot
derail the wait:

```dart
await sync.waitUntilCaughtUp(
  timeout: const Duration(seconds: 30),
  onProgress: (p) =>
      setState(() => _status = 'syncing ${p.localCommitId} / ${p.serverCommitId}'),
);
```

Use `SyncProgressListener` (§3) when you want to observe sync for the life of
the app; use `waitUntilCaughtUp` when you want to block one operation until
the data is there.

---

## 5. Read receipts are eventually consistent

`markReadByMe` / `readBy` / `readReceipts` are **shared-key writes** that ride
the same sync + notification pipeline as any other item. So `readBy` is an
**eventually-consistent local view**: a "seen by" indicator lags until the
receipt has synced back to the item's owner. If receipts never appear at all,
check sync scoping (§1) first — a wedged sync stops receipts like everything
else.

---

## Canonical example

<!-- pyml disable-num-lines 2 md013-->
- [packages/at_client_flutter/examples/todos/](../../../../at_client_flutter/examples/todos/README.md) — an `AtCollection<T>` app driving sync, shares, and read receipts through the widget stack.
