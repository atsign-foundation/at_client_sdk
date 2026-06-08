# Changelog — atsign-dart-sdk

All notable changes to this skill are documented here.

## 1.0.0 — 2026-06-02

Initial release.

- `AtCollection<T>` — full CRUD, `CItem<T>`, `Query<T>`, sub-collections, read receipts, event streams
- `wherePath` / `PathField<T>` typed predicates
- `watchWithTree` / `watchWithSub` for deep multi-level hierarchies
- `at_client_flutter` auth — all 4 dialog flows (CRAM, atKeys file, device keychain, APKAM)
- `AtClientManager` post-auth setup
- Package selection guide (`at_client`, `at_client_flutter`, `at_auth`, `at_chops`, `at_cli_commons`)
- Domain-object patterns (`toJson`/`fromJson`, `registerFactory`, `typeTag`)
- Unit testing without a live atServer (`collections_test_hooks.dart`)
- Architecture decision guide: `AtCollection<T>` vs Notifications + SQLite
- 10 common pitfalls with fixes
- Deprecation guide: `AtCollectionModel`, `at_common_flutter`, `at_backupkey_flutter`
