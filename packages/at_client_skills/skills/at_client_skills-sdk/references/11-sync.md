# Sync & Sync Lifecycle

`AtCollection<T>` reads are **local-only**; every write and every cross-atSign
delivery (shares, updates, read receipts, `watch()` re-emits) depends on
`SyncService`. Two things a real app must get right: **scope sync to your
namespace**, and understand the **asynchronous lifecycle**.

---

## 1. Scope sync to your namespace (`syncRegex`) — required

By default `AtClientPreference.syncRegex` is `null`, which means sync covers the
atSign's **entire** keystore — including keys left over from other apps and
namespaces on the same atSign. On any atSign that has been used by more than one
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
  ..syncRegex = 'my_namespace'   // scope sync to THIS app's keys
  ..commitLogPath = dir.path
  ..hiveStoragePath = dir.path;
```

The atServer always syncs **reserved keys** (pkam / encryption / public /
`shared_key` / `cached:`) regardless of the regex, so scoping does **not** break
sharing or decryption — it only excludes other apps' unrelated keys.

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
  or atSign still surfaces within a minute even when the live push didn't land.

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
    if (p.syncStatus == SyncStatus.success) onSynced();
  }
}

final sync = AtClientManager.getInstance().syncService;
final listener = _SyncedListener(() => print('synced'));
sync.addProgressListener(listener);
// ... later:
sync.removeProgressListener(listener);
```

`SyncProgress` carries `syncStatus` (`SyncStatus`:
`started` / `notStarted` / `inProgress` / `success` / `failure`),
`localCommitId`, `serverCommitId`, `pendingPushCount`, and `atClientException`.

---

## 4. Read receipts are eventually consistent

`markReadByMe` / `readBy` / `readReceipts` are **shared-key writes** that ride
the same sync + notification pipeline as any other item. So `readBy` is an
**eventually-consistent local view**: a "seen by" indicator lags until the
receipt has synced back to the item's owner. If receipts never appear at all,
check sync scoping (§1) first — a wedged sync stops receipts like everything
else.

---

## Canonical example

<!-- pyml disable-num-lines 2 md013-->
- [packages/at_client_flutter/examples/todos/](../../packages/at_client_flutter/examples/todos/README.md) — an `AtCollection<T>` app driving sync, shares, and read receipts through the widget stack.
