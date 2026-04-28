# Flutter Todos App — Implementation Plan

## Context

Build a Flutter app that replicates the feature set of the TUI
`packages/at_client/example/bin/collections_todos.dart`, and is
**interoperable** with it over the atPlatform — i.e. Alice running the TUI and
Bob running this Flutter app can share todos and notes between them as if they
were using the same app.

Interoperability contract (non-negotiable — must match the TUI exactly):

| Contract item           | Value                                                 |
|-------------------------|-------------------------------------------------------|
| Namespace               | `todos.demos`                                         |
| Todos collection key    | `todos.todos.demos`                                   |
| Notes collection key    | `notes.todos.demos`                                   |
| Type names              | `'Todo'`, `'TodoNote'`                                |
| `Todo` JSON schema      | `title`, `description`, `done`, `dueDate` (ISO-8601)  |
| `TodoNote` JSON schema  | `note`, `todoId`                                      |
| Note audience rule      | `{todo.owner, ...todo.sharedWith} \ {self}`           |
| Default expiration      | 365 days                                              |
| RemoteLocalPref         | `remoteOnly`                                          |

If any of these drift, the two apps stop sharing data cleanly.

## Scaffold (already done)

- `packages/at_client_flutter/examples/todos/` created via `flutter create`
- `pubspec.yaml` has path overrides for `at_client`, `at_auth`, `at_lookup`,
  `at_commons`, `at_chops`, and `at_client_flutter` (via `path: ../../`)
- `flutter pub get` resolves cleanly

## Feature list (mirrors the TUI)

Core:
- Onboard / load an atSign (keychain, APKAM, file, or new-atSign registration)
- List todos (sorted by due date, nulls last)
- Create / update / delete a todo
- Toggle `done`
- Set / change `dueDate` (default 7 days out on create)
- Share a todo with additional atSigns (without un-sharing existing recipients)
- Schedule visibility (`availableAt`) — delay when shared copies become visible

Notes:
- Add, update, delete notes on any todo the user has access to
- Notes are shared with `{todo.owner, ...todo.sharedWith} \ {self}` — must use
  the same `_noteAudience` rule as the TUI
- Users may only update/delete notes they own

Live behaviour:
- Subscribe to `collection.events` and `notesCollection.events`
- On `CItemUpdated` / `CItemDeleted`: refresh corresponding list
- On `CReadReceipt`: surface in UI (e.g. checkmark or list)
- Auto-send read receipts the first time an item is fetched

Display details:
- Colour-code atSigns (stable assignment from a palette; self is bold orange)
- Show Due and Created timestamps with HH:MM:SS
- Show `sharedWith` and `readBy` sets per todo
- Notes grouped under their parent todo, sorted, with owner + `createdAt`

## Flutter-specific adaptations

Input model shifts from typed commands to touch-first UI:

| TUI command                | Flutter UX equivalent                            |
|----------------------------|--------------------------------------------------|
| `create`                   | FAB → modal form (title / desc / share / due)    |
| `update N`                 | Tap todo → edit screen                           |
| `done N`                   | Tap checkbox on the row                          |
| `delete N` / `delete N.M`  | Swipe-to-delete on todo row / note row           |
| `note N`, `updatenote N.M` | "+" in notes section / tap-to-edit on note       |
| `share N`                  | Share icon on todo → modal with chip input       |
| `schedule N`               | Schedule icon → date-time picker                 |
| `keys` (debug)             | Hidden debug screen, reachable from a menu       |

Onboarding mirrors the existing `at_client_flutter/example` — four entry
points: login-with-keychain, APKAM, onboard-new-atSign, login-from-file.
Once onboarded, push into the todos screen.

## Code-reuse strategy

1. **Copy `Todo` and `TodoNote`** from
   `packages/at_client/example/lib/domain_objects.dart` into
   `lib/models/todo.dart`. They are pure Dart with `toJson` / `fromJson`. Do
   **not** depend on `at_client_examples` — it has CLI-only dependencies.
2. **Reuse `AtCollection` directly** — it already runs on Flutter. Wrap it
   in a `TodosService` class that holds the two collections, exposes live
   `Stream<List<CItem<Todo>>>` and `Stream<Map<String, List<CItem<TodoNote>>>>`,
   and handles the read-receipt + refresh-on-event plumbing.
3. **Port the atSign-colour scheme** — trivially translatable from the TUI's
   `_AtsignColors` to a Flutter `Color` assigner (same pastel palette, same
   "self is orange" rule). Use `Color.fromARGB` rather than ANSI codes.
4. **Port the note-audience helper** verbatim — the rule must be identical
   across both apps for interop.

## Implementation phases

Suggested order (each could be its own commit or small PR):

1. **Onboarding shell** — copy `main.dart` / `walkthrough.dart` skeleton from
   `at_client_flutter/example`; change namespace to `todos.demos`; land the
   "logged-in" home route with a blank Scaffold placeholder.
2. **Models + `TodosService`** — port `Todo`, `TodoNote`, set up both
   `AtCollection`s, register factories, expose `ValueNotifier<List<CItem<Todo>>>`
   and a notes map. Wire `refreshTodos` / `_refreshNotes` methods.
3. **Todos list screen** — `ListView` backed by the service's notifier; each
   row shows `done`, title, due. FAB opens a modal for create. Row tap opens
   detail.
4. **Create / edit form** — title + description + due-date picker +
   comma-separated atSigns field. Calls `collection.create` + `collection.put`.
5. **Todo detail / notes screen** — shows todo metadata, list of notes below,
   input at the bottom to add a note. Tap a note to edit (if owner), swipe to
   delete.
6. **Live events wiring** — subscribe in `TodosService.init()`; update
   notifiers on each event so all screens reactively refresh.
7. **Share & schedule dialogs** — share modal uses `unshareWithOthers: false`;
   schedule modal uses `availableAt`.
8. **Read receipts + atSign colouring** — port receipt auto-send, colour
   assignment, display of `readBy`.
9. **Polish** — empty states, error SnackBars, loading indicators, "busy"
   guard (mirrors TUI's `_handlerRunning`).

## Critical files and references

To be read / ported / imitated while building:

- `packages/at_client/example/bin/collections_todos.dart` — source of truth
  for behaviour. Especially: `_noteAudience` (line ~710),
  `_compareByDue`, the event listeners (line ~270), the read-receipt logic
  in `refreshTodos`.
- `packages/at_client/example/lib/domain_objects.dart` — `Todo` / `TodoNote`.
- `packages/at_client_flutter/example/lib/main.dart` — onboarding shell.
- `packages/at_client_flutter/example/lib/walkthrough.dart` — keychain /
  APKAM / file-load helpers.
- `packages/at_client/lib/src/collections/collections.dart` — `AtCollection`
  API surface (renames on `gkc-enhance-api` branch: `getItems`, `getItemsList`,
  single-result `get`, `create`, static `registerFactory`).

## Open questions to resolve during implementation

- **State management**: stick with `ValueNotifier`/`ChangeNotifier` +
  `ListenableBuilder` (zero extra deps), or bring in `provider` / `riverpod`?
  Default: no extra deps unless the screens demand it.
- **One-screen vs two-screen**: single list with expandable notes, or
  list → detail navigation? Default: detail screen, matches mobile norms.
- **Platforms**: target all `flutter create` scaffolds or drop some (e.g.
  web, windows) to reduce surface? Default: leave all platforms for parity
  with the existing example, revisit later.
- **Atsign entry for sharing**: free-text chip input, or contact picker via
  `at_contact` / `at_contacts_flutter`? Default: free text for the first pass.

## Verification

End-to-end interop test: run TUI on machine A as `@alice`, Flutter app on
machine B as `@bob` (both pointed at the same root domain and namespace
`todos.demos`).

1. Alice creates a todo shared with Bob → Bob sees it in the Flutter list.
2. Bob toggles done on it → Alice's TUI reflects it.
3. Alice adds a note → Bob sees it appear under the todo (reactive).
4. Bob adds a note → Alice sees it, and `readBy` eventually updates on Bob's
   side when Alice's TUI auto-sends a read receipt.
5. Bob deletes his own note → disappears on Alice's side.
6. Alice unshares Bob → todo disappears from Bob's list.

Also: `flutter analyze` must be clean, and the app must run on at least one
of {macOS, iOS, Android}.
