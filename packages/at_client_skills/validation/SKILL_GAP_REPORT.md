# `at_client_skills-sdk` — Skill Gap Report

Gaps found while building **TeamBoard** — a shared task-board Flutter app on the
atPlatform (iOS/Android/macOS) using the modern `AtCollection<T>` API.

The skill covers the **happy-path API surface** well: collections, queries,
sub-collections, the event streams, `EventSource` (including the correct note
that sub-collections inherit the parent's `EventSource`), and the four Flutter
auth dialogs. The gaps are in the **distributed-systems runtime** a real
collaborative app depends on: sync configuration and lifecycle, the real-time
delivery chain, the Flutter stream-holding rule, and failure/troubleshooting
modes.

Each gap below lists the **symptom** (concrete evidence) and **what the skill is
missing**. Legend: 🔴 blocker · 🟠 major · 🟡 minor.

---

## Summary

| # | Gap | Sev |
|---|-----|-----|
| 1 | `AtClientPreference.syncRegex` / sync scoping not documented — unscoped sync wedges | 🔴 |
| 2 | No sync-lifecycle documentation (reads are local; when/how sync runs; `SyncProgressListener`) | 🔴 |
| 3 | Flutter rule "hold the `watch()` stream; never create it in `build()`" not stated | 🔴 |
| 4 | No real-time delivery-chain model and no "shared item doesn't appear" troubleshooting | 🔴 |
| 5 | Read receipts presented as local/synchronous, not as shared-key writes on the sync pipeline | 🟠 |
| 6 | Test-hooks import path is wrong (`src/…` instead of `at_client.dart`) | 🟠 |
| 7 | Collaboration/ownership model (owner-writes-only) never stated | 🟠 |
| 8 | No headless/CLI auth (`CLIBase` / `at_cli_commons`) or live integration-test pattern | 🟠 |
| 9 | No atSign activation / atDirectory prerequisites | 🟠 |
| 10 | macOS `network.client` entitlement omitted | 🟠 |
| 11 | Multi-atSign-in-one-process fragility not covered | 🟡 |
| 12 | Headless stdout flush on `exit()` not noted | 🟡 |

---

## Detail

### 1. 🔴 `syncRegex` / sync scoping is undocumented

**Symptom.** With the default preference, `SyncService` never completes:
`SyncStatus.inProgress` with `keysSent=0`, repeated indefinitely, never
`success`. New items are never pushed and shared items never arrive — shares,
card edits, and read receipts all silently fail to propagate.

**Cause.** With `AtClientPreference.syncRegex == null`, sync covers the atSign's
**entire** keystore — including unrelated keys left over from other apps and
namespaces on the same atSign — and stalls on them. A real-world atSign
accumulates this cross-app state over time.

**What's needed.** Document `AtClientPreference.syncRegex = '<namespace>'` to
scope sync to the app's own keys. State that:
- sync is **not** namespace-isolated by default, so an unrelated/dangling key
  can wedge sync for the whole app;
- the atServer always syncs reserved keys (pkam/encryption/public/`shared_key`/
  `cached:`) regardless of the regex, so scoping does **not** break sharing or
  decryption;
- the convention is the leading-dot namespace form used by the SDK's own
  functional tests and production atApps (e.g. `syncRegex = '.wavi'`).

Scoping sync to the namespace is the difference between a working and a
non-working collaborative app on any atSign that has been used by more than one
app.

---

### 2. 🔴 No sync-lifecycle documentation

**Symptom.** No way to reason about *when* a write has reached the server or why
a read returns stale/empty data.

**What's needed.** A "sync lifecycle" reference stating that:
- all reads are **local-only** against a synced cache;
- writes sync in the **background**;
- sync cadence is `AtClientPreference.syncIntervalMins` (default 10 minutes) —
  relevant for how quickly a missed live update is reconciled;
- await/observe completion via `SyncService` + `SyncProgressListener`
  (`sync(onDone:)` is deprecated);
- this is essential for tests and headless drivers that must wait until synced
  before asserting.

---

### 3. 🔴 The Flutter stream-holding rule is not stated

**Symptom.** A collaborator's change is received and the collection fires the
corresponding `CItemUpdated`, but the `StreamBuilder` UI does not refresh — until
a hot reload / restart.

**Cause.** Creating `collection.query().watch()` **inside `build()`** mints a new
stream object on every rebuild and tears down the live subscription, so live
emissions are lost.

**What's needed.** State plainly: create a `watch()` stream **once**, hold it in
`State` (recreate only when its inputs change), and **memoise the `Query` across
rebuilds**. Never call `watch()` inside `build()`. The skill's `StreamBuilder`
snippets (§6 / ref 04) should be written this way; the canonical `examples/todos`
app already follows it (it caches its watch pipeline), but the rule is not
surfaced in the skill itself. For an SDK whose value is reactive sync, "don't
create the reactive stream in `build()`" belongs in the skill body.

---

### 4. 🔴 No delivery-chain model or troubleshooting

**Symptom.** "A shared item doesn't appear on the recipient" is the most common
real-world failure, and there is no way to localize where it breaks.

**What's needed.** Document the cross-atSign delivery chain:

```
write → local commit log → SyncService push → sender atServer
      → notification → recipient atServer → recipient monitor
      → notification handler caches incoming key → watch() re-emits → UI
```

…and a troubleshooting checklist that walks it in order: is sync healthy
(gap #1)? is the monitor connected? did the notification arrive (raw
`subscribe` probe)? did the collection fire `CItemUpdated`? did `watch()`
re-emit? did the `StreamBuilder` rebuild (gap #3)? A checklist like this turns a
multi-layer hunt into a few targeted checks.

---

### 5. 🟠 Read receipts presented as local/synchronous

**Symptom.** "Seen by" is asymmetric — the reader sees their own receipt locally
while the item owner sees "no one," because the receipt hasn't propagated.

**What's needed.** §9 should state that `markReadByMe` / `readBy` /
`readReceipts` are **shared-key writes** that travel over the same
sync/notification pipeline as any other item, and that `readBy` is an
**eventually-consistent local view** — subject to gaps #1–#4 like everything
else.

---

### 6. 🟠 Test-hooks import path is wrong

**Symptom.** The import the skill prescribes,
`import 'package:at_client/src/collections/collections_test_hooks.dart';`,
fails to compile: *"The imported library … can't have a part-of directive."*

**What's needed.** Fix §13 and ref 09 to import only
`package:at_client/at_client.dart` — the test hooks
(`collectionWithInjectedNotifications`, `clearFactoriesForTest`, …) are
re-exported from it; the `src/…` file is a `part of` and cannot be imported
directly.

---

### 7. 🟠 Collaboration/ownership model never stated

**Symptom.** Designing "a collaborator edits a shared item" hits
`ArgumentError`/`StateError` because `update`/`delete` require `owner == self`.

**What's needed.** State that `AtCollection` is **owner-writes-only**: an atSign
can only mutate keys it owns; you cannot edit another atSign's item in place.
The collaboration model is **additive** — each atSign owns what it creates;
sharing grants visibility, not write access. This is fundamental to designing
any shared feature.

---

### 8. 🟠 No headless/CLI auth or live integration-test pattern

**Symptom.** No documented way to authenticate without the GUI dialogs, so
integration tests and headless drivers have nothing to build on.

**What's needed.** Document `CLIBase.fromCommandLineArgs` (`at_cli_commons`) for
authenticating from a `.atKeys` file with no UI, and a pattern for an
integration test that runs the real collection API against a live atServer (ref
09 currently shows only mock-based tests).

---

### 9. 🟠 No atSign activation / atDirectory prerequisites

**Symptom.** Auth fails with `No entry in atDirectory for <atsign>` on atSigns
that aren't activated/registered.

**What's needed.** State that an atSign must be activated and registered in the
atDirectory before use, what the `No entry in atDirectory` error means, and how
to confirm an atSign is usable.

---

### 10. 🟠 macOS `network.client` entitlement omitted

**Symptom.** A sandboxed macOS build cannot connect to the atServer at all.

**What's needed.** Ref 05 documents the file-picker entitlement
(`com.apple.security.files.user-selected.read-only`) but omits
`com.apple.security.network.client` (required for **any** atServer connection)
and says nothing about keychain access for `biometric_storage`.

---

### 11. 🟡 Multi-atSign-in-one-process fragility

**Symptom.** Running two atSigns sequentially in one process
(`AtClientManager.reset()` + re-`init()`) hangs or stale-locks the Hive store.

**What's needed.** Guidance on switching the current atSign within one process,
the singleton `AtClientManager` semantics, and that abrupt `exit()` leaves Hive
locks that block the next session for the same atSign.

---

### 12. 🟡 Headless stdout flush on `exit()`

**Symptom.** Log lines printed before `exit(0)` are lost when stdout is
redirected.

**What's needed.** A one-line note that `exit()` does not flush buffered stdout
(`await stdout.flush()` first) — useful for anyone writing a CLI driver.

---

## Recommended additions to the skill

1. **Document `syncRegex` / sync scoping** (highest value) — `syncRegex =
   '<namespace>'`; sync is not namespace-isolated; reserved keys sync regardless.
2. **State the Flutter stream-holding rule** — hold `watch()` streams, memoise
   the `Query`, never create them in `build()`; fix the `StreamBuilder` snippets.
3. **Add a "sync lifecycle" reference** — local reads, background writes,
   `SyncProgressListener`, sync cadence.
4. **Add a "real-time delivery chain & troubleshooting" reference** — the full
   chain plus a "shared item didn't appear" checklist.
5. **Reframe read receipts** as shared-key writes / eventually-consistent views.
6. **Fix the test-hooks import** (`at_client.dart`, not the `src/` path).
7. **State the collaboration/ownership model** (owner-writes-only; additive).
8. **Add headless/CLI auth** (`CLIBase` / `at_cli_commons`) and a live
   integration-test pattern.
9. **Add atSign activation / atDirectory** prerequisites.
10. **Complete the macOS entitlements** (`network.client`; keychain).

---

*A separate `at_client` SDK defect found during this build is documented in
`AT_CLIENT_BUG_REPORT.md`. It is an SDK bug, not a skill gap, and is noted here
only as a cross-reference.*
