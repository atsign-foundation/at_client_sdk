# at_client examples

Runnable Dart examples for the [`at_client`](https://pub.dev/packages/at_client) package — the SDK for building apps on the [atPlatform](https://docs.atsign.com/).

## Prerequisites

- Two registered atSigns (two free atSigns available at [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans)) with their `.atKeys` files
- Dart SDK ≥ 3.0.0

```bash
dart pub get
```

## Running the examples

Run sender and receiver in two separate terminals. Pass `--help` to any program to see all available options:

```bash
dart run bin/collections_primitives.dart --help
```

`--role` and `--other-at-signs` can be abbreviated as `-R` and `-O`.

### Collections — primitives
Share `String` and `Map` values between atSigns.
```bash
dart run bin/collections_primitives.dart -R sender   -O @receiver
dart run bin/collections_primitives.dart -R receiver -O @sender
```

### Collections — domain objects
Share typed polymorphic domain objects (`Dog`, `Cat` as `Pet`) using registered type factories and a typed `AtCollection<Pet>`.
```bash
dart run bin/collections_domain_objects.dart -R sender   -O @receiver
dart run bin/collections_domain_objects.dart -R receiver -O @sender
```

### Collections — generic / polymorphic objects
Mix different types (`Uint8List`, `Dog`, `Cat`, `Map`, `String`) in a single untyped `AtCollection`. Also demonstrates read receipts and event-stream watching.
```bash
dart run bin/collections_generic.dart -R sender   -O @receiver
dart run bin/collections_generic.dart -R receiver -O @sender
```

### Collections — binary data
Share raw `Uint8List` binary payloads.
```bash
dart run bin/collections_binary.dart -R sender   -O @receiver
dart run bin/collections_binary.dart -R receiver -O @sender
```

### Collections — todos app
Interactive terminal-based shared todo list, built on the `nocterm`
widget framework. (There is an equivalent Flutter app in
`packages/at_client_flutter/examples/todos/` — the two apps have
been deliberately given a similar UX so you can A/B the same
scenarios across keyboard-driven and mouse-driven front-ends.)

The app is a split-pane TUI: filter chips / dashboard counts header,
list of todos on the left (keyboard-navigable), live detail pane on
the right (per-reader read-receipt timeline via
`item.receipts.query().watch()`, stitched notes via
`Query.watchWithSub`), log pane, context-sensitive footer hints.
Every command that takes input opens a modal form overlay.

```bash
dart run bin/collections_todos.dart --atsign @alice
```

Keyboard shortcuts (from the list pane):

| Key           | Action                                                      |
|---------------|-------------------------------------------------------------|
| ↑ ↓ / j k     | Move selection                                              |
| g / G         | First / last todo                                           |
| ⏎ or →        | Focus detail pane                                           |
| Esc or ←      | Back to list pane                                           |
| c             | Create todo (modal form)                                    |
| e             | Edit selected todo (modal form)                             |
| d             | Delete selected todo (modal confirm)                        |
| space         | Toggle done on selected                                     |
| n             | Add note to selected (modal form)                           |
| s             | Share selected — add atSigns (modal form)                   |
| u             | Set due date (modal form, YYYY-MM-DD)                       |
| S             | Schedule visibility via `availableAt` (modal form, seconds) |
| r             | Reverse sort direction                                      |
| /             | Live-narrow find bar                                        |
| m or Alt-M    | Open command menu (searchable)                              |
| ?             | Open help overlay                                           |
| q             | Quit                                                        |

The command menu (`m`) lists every shortcut and also includes
`Cleanup orphans` (wraps `collection.cleanupOrphans()`) and `Stats`
(composes `.count` / `.any` / `.firstOrNull` / `.groupBy` terminals
on the active query). Presets (`All` / `Mine` / `Shared with me` /
`Open` / `Done` / `Overdue`) are live `Query<Todo>` values — tapping
one swaps the stream source; the list re-narrows live as shared
todos come in.

Shared TUI plumbing (palette, presets, typedefs) lives under
`lib/todos_tui/`; the entry point and widget tree are in
`bin/collections_todos.dart`.

### Dockerstats — 3-level sub-collections, streaming
Publishes a snapshot per docker container per polling cycle into a
tree of typed sub-collections (`nodes` → `atsigns` → `samples`)
shared with N other atSigns. The publisher uses
`AtCollection.upsert` so it's safely re-runnable within the
collection's TTL; the subscriber uses `AtCollection.getDescendant`
to fetch typed leaves in one call when a `CSubItemUpdated` event
fires. Pairs with the Flutter dashboard at
`packages/at_client_flutter/examples/dockerstats/`.

Real mode shells out to the `docker` CLI; simulate mode synthesises
fake hosts and atSigns via a bounded random walk, useful for chart-UI
development without running containers.
```bash
# Publisher — real (requires `docker` on PATH):
dart run bin/dockerstats_publish.dart \
    -a @alice -P 5s --other-at-signs @bob

# Publisher — simulated multi-host fanout:
dart run bin/dockerstats_publish.dart \
    -a @alice -P 2s --other-at-signs @bob \
    --simulate --simulate-hosts 3

# Subscriber — prints one line per arriving sample:
dart run bin/dockerstats_subscribe.dart -a @bob
```
`-P` is the polling interval. Samples expire after 1 minute so
receivers see a rolling window without any client-side eviction;
the structural nodes (`atsigns` and `nodes` levels) carry a
1-hour TTL so the tree itself doesn't churn at the sample cadence.
The subscriber is a CLI counterpart to the Flutter dashboard —
useful for verifying publisher↔receiver round-trip without spinning
up the Flutter app.

### Notifications
Fire-and-forget messaging via `NotificationService`.
```bash
dart run bin/notifications.dart -R sender   -O @receiver
dart run bin/notifications.dart -R receiver -O @sender
```

### RPCs
RPC-style method invocation between atSigns.
```bash
dart run bin/rpcs.dart -R sender   -O @receiver
dart run bin/rpcs.dart -R receiver -O @sender
```

## Key concepts

- **`AtClient`** — authenticates with an atServer and provides encrypted key-value get/put/notify operations.
- **`AtCollection<T>`** — higher-level API for sharing typed, expiring collections with other atSigns; supports read receipts and event streams.
- **`CItem<T>`** — wrapper around a single collection item with value, metadata (TTL, expiry), and read-receipt state.

Shared initialization logic (argument parsing, `AtClient` setup) lives in `lib/init_example_context.dart`. Domain objects used across examples are in `lib/domain_objects.dart`.
