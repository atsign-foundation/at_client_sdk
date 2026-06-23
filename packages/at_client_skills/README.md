# at_client_skills

AI agent skill for the [Atsign](https://atsign.com) `at_client` SDK. Gives AI
coding agents accurate, up-to-date knowledge of `at_client` and
`at_client_flutter` — covering `AtCollection<T>`, auth flows, querying,
sub-collections, testing patterns, and common pitfalls.

Works with Claude Code, Cursor, GitHub Copilot, Cline, and any agent supporting
the [agentskills.io](https://agentskills.io) specification.

## Installation

```sh
# Add to your project
dart pub add --dev at_client_skills skills

# Install the skill into your IDE
dart run skills get
```

The skill will be installed to your IDE's skills directory (`.claude/skills/`,
`.cursor/skills/`, etc.) automatically.

## What's covered

- `AtCollection<T>` — full CRUD, `CItem<T>`, `Query<T>`, sub-collections,
  read receipts, event streams
- `wherePath` / `PathField<T>` typed predicates
- `watchWithTree` / `watchWithSub` for deep multi-level hierarchies
- `at_client_flutter` auth — all 4 dialog flows (CRAM, atKeys file,
  device keychain, APKAM)
- `AtClientManager` post-auth setup
- Package selection guide
- Domain-object patterns (`toJson`/`fromJson`, `registerFactory`, `typeTag`)
- Unit testing without a live atServer (`collections_test_hooks.dart`)
- Architecture decision guide: `AtCollection<T>` vs Notifications + SQLite
- Deprecation guide: `AtCollectionModel`, `at_common_flutter`,
  `at_backupkey_flutter`

## Keeping it up to date

```sh
dart pub upgrade at_client_skills && dart run skills get
```

## Dart/Flutter MCP Server

When the official Dart/Flutter MCP server ships resource support
<!-- pyml disable-next-line md013-->
([flutter.dev/go/packaged-ai-assets](https://flutter.dev/go/packaged-ai-assets)), this package will be updated to expose the skill content as MCP resources — no action needed on your end.

## Validating the skill (maintainers)

Maintainers can regression-test the skill end-to-end by having an agent build a
deliberately comprehensive app from the skill alone. See
[`validation/teamboard-skill-test.md`](validation/teamboard-skill-test.md) for
the setup recipe and build prompt. (Not shipped to pub — see `.pubignore`.)
