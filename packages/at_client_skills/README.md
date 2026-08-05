# at_client_skills

AI agent skill for the [Atsign](https://atsign.com) `at_client` SDK. Gives AI
coding agents accurate, up-to-date knowledge of `at_client` and
`at_client_flutter` — covering `AtCollection<T>`, auth flows, querying,
sub-collections, testing patterns, and common pitfalls.

Works with Claude Code, Cursor, GitHub Copilot, Cline, and any agent supporting
the [agentskills.io](https://agentskills.io) specification.

## Installation

Two packages work together:

| Package | What it does |
| --- | --- |
| **`at_client_skills`** (this package) | Ships the skill content — `SKILL.md` and its reference docs. There is no Dart API to import. |
| **[`skills`](https://pub.dev/packages/skills)** | The CLI that scans your dependencies for `skills/` directories and installs what it finds into your agent's skills directory. Without it there is no `skills` command to run. |

Prerequisites: Dart SDK 3.5.0 or newer (required by the `skills` CLI), a
project with a `pubspec.yaml`, and an agent that reads a skills directory.

**1. Add both packages** as dev dependencies. In Flutter projects
`flutter pub add` works identically:

```sh
dart pub add --dev at_client_skills skills
```

**2. Install the skill** into your agent's skills directory:

```sh
dart run skills get
```

The CLI runs `pub get` if needed, scans your dependencies for `skills/`
directories, and installs what it finds — so this picks up every
skill-providing package in your project, not just this one.

**3. Verify** the install:

```sh
dart run skills list
```

The skill lands in whichever directory your agent uses — `.claude/skills/`,
`.cursor/skills/`, `.cline/skills/`, `.github/skills/`, `.opencode/skills/`,
or `.agent/skills/`.

**4. Reload your agent** so it picks up the new skill.

### Alternative: activate the CLI globally

If you would rather not add `skills` to every project:

```sh
dart pub global activate skills      # once per machine
dart pub add --dev at_client_skills  # still needed — it carries the content
skills get                           # note: no `dart run` prefix
```

This requires `~/.pub-cache/bin` on your `PATH`.

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
- RPC between atsigns (`AtRpc` / `AtRpcClient` request/response)
- Headless agents and multi-instance coordination (`CLIBase`, immutable-mutex,
  no-sync scaling)
- Remote vs local atServer operations (`remoteLocalPref`, `useRemoteAtServer`,
  `bypassCache`)
- Deprecation guide: `AtCollectionModel`, `at_common_flutter`,
  `at_backupkey_flutter`

## Keeping it up to date

```sh
dart pub upgrade at_client_skills && dart run skills get
```

Other `skills` commands: `list` shows what is installed, `prune` removes skills
for packages no longer in your dependency tree, and `remove` uninstalls all
managed skills.

## Dart/Flutter MCP Server

When the official Dart/Flutter MCP server ships resource support
<!-- pyml disable-next-line md013-->
([flutter.dev/go/packaged-ai-assets](https://flutter.dev/go/packaged-ai-assets)), this package will be updated to expose the skill content as MCP resources — no action needed on your end.
