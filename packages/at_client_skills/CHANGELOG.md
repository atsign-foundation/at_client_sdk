# Changelog — at_client_skills

## 1.4.0 — unreleased

- Warn that an RPC `call()` has no timeout of its own and waits forever on a
  peer that never answers, and bound every call in the samples.
- Use `send(idAndNamespace:)`, not the deprecated `namespace:`, and say what
  the value is — an id and a namespace joined by a dot, split at the first one.
- Document at-least-once notification delivery — replay on a stop, and
  handlers that must tolerate running twice.
- Document a stopped sync service — `SyncProgress.stopped`, and
  `waitUntilCaughtUp` ending with `StoppedException` too.
- Document `StoppedException` — why it is not an `AtException`, and catch
  order.
- Document stopping a client — what `stop()` ends, that it does not drain, and
  the re-push a stop can leave behind.
- Follow at_client_flutter 2.0 in the auth flows — dialogs hand back the
  `AtClient`, the app owns it, and nothing imports `at_auth`.
- Document the AtClient lifecycle — the `Atsign` verbs, the platform bundle a
  client is built from, connection state, and `AtClientManager.use`.
- Drop `at_auth` and `setCurrentAtSign` across the package map, headless-agent
  and sync material, and name `hiveStoragePath` / `commitLogPath` as
  deprecated.
- Document public keys — `AtKey.public`, signed-not-encrypted values, and the
  always-remote `plookup` read path.
- Document notification delivery confirmation — `getStatus` / `fetch`, the
  two-value status enum, and the expiration window.
- Document headless enrolment — where the passcode comes from, who may
  approve, and least-privilege namespaces.
- Document error handling — the exception families, `getTraceMessage()` over
  `toString()`, and `CollectionOpException` partial failures.
- Document waiting for sync to settle — `waitUntilCaughtUp`, its snapshot
  semantics, and the mandatory `timeout`.
- Document the deprecated `AtClient` methods — the `notify*` / `startMonitor`
  family, the moved file-transfer and stream methods, and the deprecated
  `AtClientPreference` fields.
- Document `AtRpcCallbacks` — the route for a peer that both answers and makes
  requests, and that `sendRequest` widens the allow list.
- Note that NoPorts carries its own access control, with a pointer to
  `noports_core` rather than a description of its internals.
- Bring the skill within the Agent Skills spec — the `description` was over
  the 1024-character limit, and sync setup moves out of Flutter Auth to where
  it applies to any client.
- Extend the evals to cover the new material.

## 1.3.0 — 2026-07-31

- Document RPC between atsigns — `AtRpc` / `AtRpcClient` request/response
  (new `references/13-rpc.md`).
- Document headless agents and multi-instance coordination — `CLIBase` auth,
  per-process storage paths, the immutable-mutex pattern, and stateless
  scaling with `ServiceFactoryWithNoOpSyncService`
  (new `references/14-multi-agent.md`).
- Document remote vs local atServer operations — client-wide
  `remoteLocalPref`, per-operation `useRemoteAtServer`, and `bypassCache`
  (new `references/12-remote-atserver.md`).
- Document the rule to never pin `at_client` / `at_client_flutter` versions —
  install with `dart pub add` instead.
- Clarify the macOS `network.server` entitlement is only needed when the app
  opens a listening socket (e.g. NoPorts tunnels).
- Add `noports_core` and `at_stream` (pre-release) to the package map.
- Document that `at_onboarding_flutter` is discontinued — use `at_client_flutter`.
- Add evals covering the new content, and tighten the owner-writes-only and
  activation evals.
- Document the `skills` CLI prerequisite and the full install steps in the
  README.

## 1.2.0 — 2026-07-07

- Document sync scoping (`syncRegex`) and the sync lifecycle
  (new `references/11-sync.md`).
- Document the rule to hold `watch()` streams in `State`, never in `build()`,
  and fix the `StreamBuilder` snippets.
- Document the owner-writes-only collaboration/ownership model.
- Document the atSign activation / atDirectory prerequisite.

## 1.1.0 — 2026-06-23

- Add `user-invocable: true` so the skill registers as a slash command.
- Document the required macOS entitlements in `references/05-flutter-auth.md`:
  `network.client` (connect to the atServer) and
  `files.user-selected.read-only` (the `.atKeys` file picker).
- Fix the test-hooks import: the helpers come from `at_client.dart`, not the
  `src/collections/...` `part of` file (`SKILL.md`, `references/09`).
- Add an eval covering the macOS entitlement fix.

## 1.0.0 — 2026-06-08

Initial release.

- `AtCollection<T>` — full CRUD, `CItem<T>`, `Query<T>`, sub-collections,
  read receipts, event streams
- `wherePath` / `PathField<T>` typed predicates
- `watchWithTree` / `watchWithSub` for deep multi-level hierarchies
- `at_client_flutter` auth — all 4 dialog flows (CRAM, atKeys file,
  device keychain, APKAM)
- `AtClientManager` post-auth setup
- Package selection guide (`at_client`, `at_client_flutter`, `at_auth`,
  `at_chops`, `at_cli_commons`)
- Domain-object patterns (`toJson`/`fromJson`, `registerFactory`, `typeTag`)
- Unit testing without a live atServer (`collections_test_hooks.dart`)
- Architecture decision guide: `AtCollection<T>` vs Notifications + SQLite
- 10 common pitfalls with fixes
- Deprecation guide: `AtCollectionModel`, `at_common_flutter`,
  `at_backupkey_flutter`
