# todos — Flutter reference app for `AtCollection<T>`

A multi-platform (iOS / Android / macOS / Linux / Windows)
Flutter app that drives a shared, end-to-end-encrypted todo list
across atSigns. It's the **idiomatic Flutter consumer** of the
`AtCollection<T>` API — written to be the first place to look when
you're building a real Flutter application on the
[atPlatform](https://docs.atsign.com/) and want to see every common
collection-shaped pattern wired up correctly.

> **Web is not a supported target.** The Flutter scaffold
> generated a `web/` directory but `at_client` and
> `at_client_flutter` don't run on web — atSign onboarding and
> key storage rely on platform plugins that have no web
> implementation today. Don't try `flutter run -d chrome`.

## Where this fits

- **`AtCollection<T>` API** — full reference: the
  [`at_client` README](../../../at_client/README.md) (architecture,
  CRUD verbs, queries, sub-collections, events, read receipts,
  timer events). Deep-dive design notes:
  [`AtCollection_API_Assessment.md`](../../../at_client/AtCollection_API_Assessment.md).
- **CLI / TUI sibling app**:
  [`packages/at_client/example/bin/collections_todos.dart`](../../../at_client/example/bin/collections_todos.dart)
  (run from
  [`packages/at_client/example/`](../../../at_client/example/README.md)
  — see "Collections — todos app"). Same domain shape, same wire
  format, same audience. The two apps are interop-compatible: log
  into both with two atSigns, share a todo from one, and the other
  side picks it up live.
- **Flutter onboarding plumbing**:
  [`at_client_flutter`](../../README.md) (key-chain storage, OTP
  entry dialogs, atSign-selection dialogs).

If you've never touched the platform: read the
[`at_client` README's "atSign lifecycle (short version)"](../../../at_client/README.md)
section first — this app drives that flow via Flutter dialogs in
[`lib/onboarding.dart`](lib/onboarding.dart) but the underlying
concepts are platform-agnostic.

## What it demonstrates

Every interesting bit of `AtCollection<T>` is exercised by
[`lib/services/todos_service.dart`](lib/services/todos_service.dart) — that
file is annotated to act as a guided tour. Highlights:

| Feature                                    | Where                                                           |
|--------------------------------------------|-----------------------------------------------------------------|
| Typed `AtCollection<T>` + `fromJson` / `typeTag` | `setUpCollections()` — `atClient.collection<Todo>(...)`     |
| `cleanupOrphansOnCreation: true`           | same                                                            |
| Sub-collections (notes per todo)           | `_notesSubFor(todo)` → `collection.subCollection<TodoNote>(...)` |
| `Query<T>` builder + presets               | [`lib/services/todo_presets.dart`](lib/services/todo_presets.dart) — `where` / `orderBy` chains |
| `Query.watch()` (live reactive)            | `watchTodosWithNotes(q)` and `watchCount(q)`                    |
| `Query.watchWithSub<U>` (parent + children) | `watchTodosWithNotes(q)`                                       |
| `Query.watchSingle(id, owner)` (single record) | `watchSingle()` — drives the detail screen                  |
| `sharedWith` + `updateSharedWith`          | "Share" UI in `screens/todo_detail.dart`                        |
| Read receipts (`markReadByMe` / `readBy`)  | detail screen + per-row badges                                  |
| `availableAt` / scheduled visibility       | new-todo form (optional)                                        |
| Local CEvent emission (sync UI redraw)     | implicit — every `create` / `update` / `delete` re-emits via `Query.watch` immediately |

Models and the wire format are deliberately byte-compatible with
the CLI app — see the comment at the top of
[`lib/models/todo.dart`](lib/models/todo.dart). Both apps register
`Todo` and `TodoNote` factories with the same `typeTag` strings so
records round-trip cleanly between them.

## Running

### Prerequisites

- Flutter SDK installed and a target platform configured
  (`flutter doctor` should be clean).
- One or two registered atSigns. Free atSigns at
  [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans);
  paid / custom at [my.atsign.com](https://my.atsign.com). For a
  meaningful demo of sharing, register two and onboard each on a
  different device (or the same device pointed at separate
  application-support directories so each instance gets its own
  keychain entry).

### First run

```bash
cd packages/at_client_flutter/examples/todos
flutter pub get
flutter run            # picks the connected device / first available platform
```

The launch screen offers two onboarding paths:

- **Continue with keychain** — picks an atSign already
  device-onboarded via `at_client_flutter`'s `KeychainStorage`. Use
  this on second-and-later launches.
- **Onboard from .atKeys file** — first-launch path. Choose the
  `.atKeys` file generated when the atSign was originally
  onboarded (or onboard it now via the `at_onboarding_flutter`
  flow if you haven't yet).

After login the home screen is a streamed list of todos. Tap one
to drill into the detail screen (notes, read receipts, sharing
controls).

### Multi-device demo

To see live sharing:

1. Run the app on Device A, log in as `@alice`.
2. Run the app on Device B (or the same device with a different
   build target), log in as `@bob`.
3. On A: create a todo with `sharedWith: {@bob}`. On B: it appears
   within ~1–3 s (sync interval).
4. On B: tap the todo to mark it read; on A you'll see `@bob`'s
   read receipt show up live in the detail panel.
5. Edit / delete on either side; the other syncs.

You can do the same demo cross-app: run the CLI sibling
([`collections_todos.dart`](../../../at_client/example/bin/collections_todos.dart))
as `@alice` and the Flutter app as `@bob`, share between them. The
data shape is identical.

## Source tour

| Path                                  | What lives there                                                         |
|---------------------------------------|--------------------------------------------------------------------------|
| `lib/main.dart`                       | App entry, `MaterialApp`, launch / onboarding switch                     |
| `lib/onboarding.dart`                 | Keychain + .atKeys file login flows; AtClient construction               |
| `lib/services/todos_service.dart`     | All `AtCollection<T>` interaction — read this first                      |
| `lib/services/todo_presets.dart`      | The `TodoPreset` registry: filter chips wrap `Query<Todo>` values        |
| `lib/services/atsign_colors.dart`     | Deterministic color per atSign for share-pill rendering                  |
| `lib/models/todo.dart`                | `Todo` and `TodoNote` domain types — wire-compatible with the CLI app    |
| `lib/screens/todos_home.dart`         | List view, filter chips, find bar, presets, navigation                   |
| `lib/screens/todo_detail.dart`        | Detail pane: notes, sharing, due date, read receipts, schedule           |
| `lib/widgets/todo_form.dart`          | Modal form for create / edit                                             |
| `lib/widgets/atsign_text.dart`        | Per-atSign-coloured chip used everywhere atSigns are rendered            |

## Tests

```bash
flutter test --concurrency=1
```

Widget tests live under [`test/`](test/). The pure-Dart
`AtCollection<T>` surface is unit-tested in
[`packages/at_client/test/`](../../../at_client/test/) — running
those alongside the Flutter widget tests gives full coverage of
both layers.

## Further reading

- [atPlatform overview](https://docs.atsign.com/) — protocol-level
  primer.
- [`at_client` README](../../../at_client/README.md) — the SDK
  this app sits on; covers architecture, CRUD, queries, events,
  the local-first sync model, and onboarding.
- [`AtCollection_API_Assessment.md`](../../../at_client/AtCollection_API_Assessment.md)
  — design rationale, every API decision argued against
  alternatives, and the worked tree-depth math that bounds
  `subCollection` nesting.
- [`packages/at_client/example/README.md`](../../../at_client/example/README.md)
  — every CLI example, including the sibling
  [`collections_todos.dart`](../../../at_client/example/README.md#collections--todos-app).
