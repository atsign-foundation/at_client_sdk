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
widget framework. There is an equivalent Flutter app at
[`packages/at_client_flutter/examples/todos/`](../../at_client_flutter/examples/todos/README.md)
— the two apps have been deliberately given a similar UX so you
can A/B the same scenarios across keyboard-driven and mouse-driven
front-ends, and their wire formats are byte-compatible so logging
into both with two atSigns and sharing a todo from one shows it
live in the other.

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

### Dockerstats — notification-based live telemetry
Publishes one `docker stats` sample per container per polling cycle
as a single `notificationService.send(...)` call — no AtCollection,
no keystore writes, no sync queue. Each notification carries the
JSON-encoded sample as its body, namespaced
`sample.<container>.<host>.dockerstats.demos` so a single
subscriber regex catches every container's stream.

This is the deliberate counterpart to the AtCollection-based
examples above. It demonstrates **picking the right tool for the
job**: high-frequency observations don't belong in a typed shared
dataset — they belong on a transient delivery channel
(notifications) feeding a database designed for time series. The
companion [Flutter dashboard](../../at_client_flutter/examples/dockerstats/README.md)
shows the full pipeline: subscribe, persist to SQLite, render
charts off the local store with a five-tier roll-up for bounded
storage and uniform chart resolution.

Real mode shells out to the `docker` CLI; simulate mode synthesises
fake hosts via a bounded random walk, useful for development
without running containers.
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
`-P` is the polling interval. Notifications expire after 5 minutes
(`ttln`) so receivers that reconnect after a longer outage just
resume from the next live sample rather than replaying stale ones.

The subscriber is the CLI counterpart to the Flutter dashboard —
prints one line per arriving sample, useful for verifying
publisher↔receiver round-trip without launching the dashboard. The
full app design, roll-up table, and seed-DB workflow are in the
[Flutter dashboard's README](../../at_client_flutter/examples/dockerstats/README.md).

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
