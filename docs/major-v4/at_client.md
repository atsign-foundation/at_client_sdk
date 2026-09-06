# `at_client` 4.0.0-rc1

Last package in the v4 publish chain. Depends on `at_lookup` 4.0.0-rc1 — this branch
stacks on `st/at_lookup-v4`'s tip before any code commit lands. `at_auth ^4.0.0-rc1`
is already the correct floor on trunk. Scope here is held to **I5–I8** (D8 — this
project's own call, not a ladder default); see [`README.md`](README.md), committed
alongside this doc, for the full three-package map and the stacking order shared
across all three branches.

## Context

`at_client` is step 6 of the publish ladder
([`implementation-plan.md`](../projects/wasm/implementation-plan.md) §10), Phase I (the
`dart:io` sweep) — but per **D8** (this project's own call, not a ladder default) this
release is held to **I5–I8**. I9–I11 (backend-neutral sync queue, dropping the direct
`hive` dependency, publish) are out of scope; `at_persistence_secondary_server` stays
on the `AtClientStorage` interface.

**This release's exit criterion is not a `wasm_gates.yaml` stanza, independently of
D8.** Even after everything below lands, the residual set still blocks: `hive` on the
sync-queue path, `archive/archive_io.dart`, and `dart:io` files I6 doesn't reach
(`at_client_impl.dart`, `remote_secondary.dart`, `monitor.dart`). A gate has to "hold a
line rather than record a backlog" — `wasm_gates.yaml` counts 7 offenders here today,
and this release doesn't clear them.

## Scope

**In:**

- **Two deletions that unblock at_lookup's T3.** `stream()` (`at_client_spec.dart:585`)
  and `sendStreamAck()` (`:590`), both `@Deprecated("Obsolete, will be removed in v4")`,
  and `RemoteSecondary.addStreamData` (`remote_secondary.dart:148`, no `@Deprecated`
  annotation but zero callers repo-wide outside its own definition). These call
  `AtConnection.getSocket()` directly — they have to go before `at_lookup` can remove
  that member.
- **I5 — Connectivity behind an injectable interface.**
  `remote_secondary.dart:14` imports `internet_connection_checker`; used at `:192`
  inside `authenticateCram`. `connectivity_listener.dart:3` imports it too, used at
  `:44-48` (`InternetConnectionChecker.createInstance`). Both call sites are already
  `@Deprecated` — evaluate deleting outright before porting to an interface. Drop
  `internet_connection_checker` from the pubspec once both are gone.
- **I6 — `File` off the public spec.** `at_client_spec.dart:664`'s `downloadFile`
  returns `Future<List<File>>` (siblings `uploadFile` and `reuploadFiles` take
  `List<File>` too, all three already `@Deprecated('Method will be removed from SDK
  since method is moved to app layer')`). Pulls `file_transfer_service.dart` and
  `stream_notification_handler.dart` with it. Resolve OQ-4 first (per the ladder) —
  these methods are already marked for removal, so I6 may be "delete," not "port."
- **I7 — Inject an `http.Client` into `file_transfer_service.dart`.** Worth doing
  independent of I6 — it's the only way to test that service, since it currently calls
  top-level `http.post`/`get` with no seam.
- **I8 — Storage backend selectable from `AtClientPreference`.**
  `storage_manager.dart:16` hardcodes `final HiveAtPersistenceFactory _factory =
  HiveAtPersistenceFactory();`. `AtPersistenceBackendId` already has `hive` and
  `sqlite` — introduce the backend choice and an opaque storage location. Remove the
  unused `keyStoreSecret` parameter (`storage_manager.dart:38`) while in the file.
  Resolve OQ-3 here.

**Deprecation sweep, same release:** ~75 `@Deprecated` annotations across
`packages/at_client/lib` at `124982684` (counted directly; the ladder's own estimate is
"~70"). The largest single item is the whole barrel-exported `src/at_collection/**`
tree (`at_collection_model.dart`, `at_collection_model_factory.dart`,
`at_json_collection_model.dart`, ...), superseded by the live `src/collections/**`
tree. `SyncIsolateManager` (`manager/sync_isolate_manager.dart:2`, `import
'dart:isolate'`) is already deprecated and goes with it.

**Close the D-12 gap:** `hiveStoragePath` was ruled deprecated in
[`decisions.md`](../projects/wasm/decisions.md):865 (D-12, 2026-09-05) but carries no
`@Deprecated` annotation at `at_client_preference.dart:10` — add it in this release
since I8 is what makes the field's replacement (an opaque storage location) real.

**Housekeeping:** `AtClientConfig.atClientVersion`
(`preference/at_client_config.dart:13`, hand-set to `'3.14.1'` today) is manually
synced to the pubspec version with nothing generating or checking it. Add a test that
fails when they drift — cheap, and this release is already touching version-adjacent
files.

**Out of scope, stated:**

- Per **D8**: `at_persistence_secondary_server` off the `AtClientStorage` interface —
  I9–I11.
- Remote-only as an injected write-through `Secondary` (D-13 in `decisions.md`).
- The P and W phases (`at_client_web`) — a new package, not this one.
- `AtClientManager` moving off its singleton to instance-based — a wide blast radius
  (`AtClientManager` is referenced in 174+ files repo-wide at `124982684`; scoping to
  actual call sites vs. incidental references is separate work) — gated on T0, which
  `plans/wasm/spike/STATUS.md` §5 reports as unbuilt (*"no `dart_test.yaml` and no
  execution gate on any branch"*).
- Hive itself stays. The gate stanza for `at_client` follows non-breaking in a later
  4.x minor, once I9–I11 land.

## Dependency floors

`at_utils: ^4.0.0`, `at_lookup: ^4.0.0-rc1` (both this ladder's earlier steps).
`at_auth: ^4.0.0-rc1` is already correct on trunk.

## A release-process risk with no owner

There is **no publish job in CI** for this package. `at_client` is absent from
`.github/workflows/at_libraries.yaml`'s matrix, and `at_lookup` is absent from
`.github/workflows/at_client_sdk.yaml`'s — so nothing in CI ever builds `at_client`
against a *resolved* (non-workspace) `at_lookup`. This is live and biting today,
independent of this release: `at_lookup: ^3.6.0` in both `at_client/pubspec.yaml:33`
and `at_onboarding_cli/pubspec.yaml:27` is a caret range, and caret ranges exclude
prereleases — neither package can currently resolve `at_lookup: 3.7.0-rc1` from a
real pub registry. Workspace resolution masks this locally because `resolution:
workspace` bypasses semver entirely for path-resolved packages. This release bumps
both to `^4.0.0-rc1`, which doesn't fix the missing CI coverage — flagging it here so
it isn't mistaken for fixed.

## Exit

- `dart analyze` clean.
- `tests/at_functional_test` green.
- `monitor_test.dart` passes **unchanged** — it stubs `getSocket()` on the concrete
  `OutboundConnection`, so an untouched pass is the proof that the one live socket
  path (`monitor.dart`, deliberately not touched by I5–I8) survived this release intact.

## Changelog

```
## 4.0.0-rc1
- BREAKING: `stream()`, `sendStreamAck()`, and `RemoteSecondary.addStreamData` removed
  (deprecated since an earlier release; superseded by `NotificationService`).
- BREAKING: connectivity checking is now injected rather than hardcoded to
  `internet_connection_checker`; the direct dependency is dropped.
- BREAKING: `AtClientPreference.hiveStoragePath` is deprecated — pass a backend and an
  opaque storage location instead. Storage backend is now selectable
  (`AtPersistenceBackendId.hive` / `.sqlite`) rather than fixed to Hive.
- Removed: the `src/at_collection/**` collection model (deprecated); use
  `src/collections/**`.
```
