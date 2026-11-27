# at_client_skills

AI agent skills for the [Atsign](https://atsign.com) `at_client` SDK. They give
AI coding agents accurate, up-to-date knowledge of `at_client` and the
platform packages an app builds on, `at_client_cli` and `at_client_flutter`.

The package ships three skills. Install all three: an agent loads the ones a
task needs.

<!-- pyml disable-num-lines 5 md013-->
| Skill | For |
| --- | --- |
| `at-client-skills-core` | Every app: data, sharing, sync, notifications, the client lifecycle |
| `at-client-skills-cli` | Dart command-line programs, daemons and headless agents (`at_client_cli`) |
| `at-client-skills-flutter` | Flutter apps (`at_client_flutter`) |

Works with any agent that reads the
[agentskills.io](https://agentskills.io) skill format.

## Installation

Two packages work together:

<!-- pyml disable-num-lines 4 md013-->
| Package | What it does |
| --- | --- |
| **`at_client_skills`** (this package) | Ships the skill content — each skill's `SKILL.md` and its reference docs. There is no Dart API to import. |
| **[`skills`](https://pub.dev/packages/skills)** | The CLI that scans your dependencies for `skills/` directories and installs what it finds into your agent's skills directory. Without it there is no `skills` command to run. |

Prerequisites: a Dart SDK recent enough for the `skills` CLI (`pub` says so if
yours is too old), a project with a `pubspec.yaml`, and an agent that reads a
skills directory.

**1. Add both packages** as dev dependencies. In Flutter projects
`flutter pub add` works identically:

```sh
dart pub add --dev at_client_skills skills
```

**2. Install the skills** into your agent's skills directory:

```sh
dart run skills get --agent claude --all
```

`--agent` names your agent; `dart run skills get --help` lists the choices.
Name it the first time: in a project with no agent directory yet, the CLI has
nothing to detect.

`--all` installs every skill without asking. Without it, the CLI asks which to
install; choose all three. The CLI scans every skill-providing package in your
project, not just this one.

**3. Verify** that all three skills are installed:

```sh
dart run skills list
```

They land in your agent's skills directory, such as `.claude/skills/`.

**4. Reload your agent** so it picks up the new skills.

### Alternative: activate the CLI globally

If you would rather not add `skills` to every project:

```sh
dart pub global activate skills      # once per machine
dart pub add --dev at_client_skills  # still needed — it carries the content
skills get --agent claude --all      # note: no `dart run` prefix
```

This requires `~/.pub-cache/bin` on your `PATH`.

## What's covered

- **Data:** `AtCollection<T>` — items, queries, sub-collections, events, read
  receipts, sharing — and when notifications with local storage fit better
- **The client:** opening, stopping and switching it, connection state, sync,
  and keyfiles
- **Sign-in and enrollment:** the Flutter dialogs, command-line activation and
  enrollment, and approving new devices
- **Post-quantum posture:** which to choose, and how an existing app moves
- **Messaging:** notifications, delivery confirmation, and RPC between atsigns
- **Headless agents:** command-line programs, and running several copies of
  one agent
- **Errors and testing:** what to catch, and unit tests without a live
  atServer
- **Upgrading:** what at_client 4.0 removed, and what replaces each
- **Packages:** which to add, and what to do when the SDK lacks something

## Keeping it up to date

```sh
dart pub upgrade at_client_skills && dart run skills get --all
```

`dart run skills --help` lists the CLI's other commands.
