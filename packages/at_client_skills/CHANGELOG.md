# Changelog — at_client_skills

## 1.4.0 — unreleased

- Catching a stop: `StoppedException` joins the family of things thrown from
  outside the `AtException` tree, with what raises it, why it is deliberately
  not an `AtException`, and the catch order that keeps a shutdown out of the
  error log. Records that `subscribe`, `subscribeFiltered` and
  `startListening` throw it outright, that `notify` lets it propagate rather
  than reporting `undelivered`, and that `waitUntilCaughtUp` ends with it when
  the sync service stops first (`references/17-error-handling.md`;
  `SKILL.md` §18).
- Stopping a client: `stop()` ends the client's timers and waits and closes
  every connection, work it cuts short fails with `StoppedException`, and a
  push the atServer accepted just before the stop is pushed again by the next
  client (`references/15-client-lifecycle.md` §7; `SKILL.md`).
- The auth flows follow at_client_flutter 2.0: every dialog hands back the
  `AtClient` it opened, the app owns it, and nothing imports `at_auth`.
  `AtAuthRequest`, `AuthResponse`, `_setupAtClient` and
  `AtClientManager.setCurrentAtSign` are gone from the skill (rewritten
  `references/05-flutter-auth.md`; `SKILL.md` §10).
- New: AtClient lifecycle — the `Atsign` verbs (`open`, `activate`, `enroll`,
  `resumeEnrollment`), the platform bundle a client is built from (`keys:`,
  `storage:` and `lookUps:`, the `AtLookUpFactory` that builds every
  connection the client opens), the connection state (`client.connection`:
  online / offline / refused, the causes, `awaitOnline`), the sync and
  notification services' start and stop, `AtClientManager.use`, and what
  `stop()` does and does not do (new `references/15-client-lifecycle.md`;
  `SKILL.md` §11; later sections renumbered).
- The package map, the headless-agent and sync references and the
  deprecation guide drop `at_auth` and `setCurrentAtSign`, and name
  `hiveStoragePath` / `commitLogPath` as deprecated in favour of a storage
  object.
- Document public keys — `AtKey.public`, signed-not-encrypted values, and the
  always-remote `plookup` read path (`references/12-remote-atserver.md`).
- Document notification delivery confirmation — `send()` → `getStatus(id)` /
  `fetch(id)`, the two-value status enum, and the expiration window
  (new `references/16-notifications.md`).
- Document headless enrolment — where the passcode comes from
  (`client.enrollments.otp` / `.spp`), that only a `__manage` holder can
  approve, and least-privilege namespaces
  (`references/15-client-lifecycle.md`).
- Document error handling — the three exception families, `getTraceMessage()`
  over `toString()`, `CollectionOpException` partial failures, and what each
  operation throws (new `references/17-error-handling.md`).
- Document waiting for sync to settle — `waitUntilCaughtUp`, its snapshot
  semantics, the mandatory `timeout`, and why polling `isSyncInProgress` is a
  check-then-act race (`references/11-sync.md`).
- Document the deprecated `AtClient` methods — the `notify*` / `startMonitor`
  family, the file-transfer and stream methods that moved to the app layer,
  the compaction jobs, `atChops`, and the deprecated `AtClientPreference`
  fields (`references/01-deprecation-guide.md`; `SKILL.md` §19).
- Document `AtRpcCallbacks` — the route for a peer that both answers and makes
  requests, the `ack` responses `call()` hides, and that `sendRequest` widens
  the allow list (`references/13-rpc.md`).
- Note that NoPorts carries its own access control (`--managers` and/or a
  `--policy-manager` atsign running an `NPA`) — a pointer to `noports_core`
  and its docs, not a description of its internals
  (`references/06-package-map.md`).
- Bring the skill within the Agent Skills spec. The `description` exceeded the
  1024-character limit; it is rewritten around what a developer asks rather
  than the API names they would only know after the answer. Sync setup and
  `waitUntilCaughtUp` move out of §10 Flutter Auth into §11, where they apply
  to any client — a headless daemon needs them just as much — and the
  duplicated Flow 3 snippet drops in favour of `references/05-flutter-auth.md`.
- Evals: the two auth evals follow the new flows; new evals cover logout /
  switching, the connection state, public keys, notification confirmation,
  headless enrolment, error handling, waiting for sync, the deprecated
  `AtClient` methods and `AtRpcCallbacks`.

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
