# Changelog — at_client_skills

## 1.2.0 — 2026-07-07

- Document sync scoping (`syncRegex`) and the sync lifecycle in a new
  `references/11-sync.md`: reads are local-only, writes sync in the background,
  scope sync to your namespace to avoid a wedged sync, and observe completion
  via `SyncProgressListener`.
- Add the Flutter rule to hold `watch()` streams in `State` — never create them
  in `build()` — and fix the `StreamBuilder` snippets accordingly.
- Document the owner-writes-only collaboration/ownership model.

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
