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
Interactive terminal-based shared todo list. (Note: there is an 
equivalent Flutter app in the at_client_flutter/examples/todos 
directory.)
Demonstrates a wide range of the `AtCollection` API: two collections  
(`Todo` and `TodoNote`), read receipts, live event streams,  
`unshareWithOthers: false`, `availableAt` scheduling,  and raw key 
inspection. Run as any atSign — todos are shared with whoever you
specify per item.
```bash
dart run bin/collections_todos.dart --atsign @alice
```

Available commands inside the app. Todo / note indexes are 1-based. Commands
that take an index require it inline (e.g. `delete 1`, `done 2`, `note 3`);
other arguments are optional and prompted if omitted.

| Command                    | Description                                                                  |
|----------------------------|------------------------------------------------------------------------------|
| `create`                   | Create a new todo. Prompts for title, description, atSigns, due (default 7d) |
| `update N`                 | Update a todo. Prompts for new title, description, and share list            |
| `delete N` or `delete N.M` | Delete todo N, or note M in todo N                                           |
| `done N`                   | Toggle the done `[x]`/`[ ]` status                                           |
| `due N [YYYY-MM-DD]`       | Set a due date                                                               |
| `note N [text…]`           | Attach a note to a todo (stored in a separate collection)                    |
| `updatenote N.M [text…]`   | Update note M in todo N; re-syncs sharing to match the parent todo           |
| `share N [@signs,…]`       | Add recipients without removing existing shares                              |
| `schedule N [seconds]`     | Delay recipient visibility (`availableAt`)                                   |
| `keys`                     | Log all raw AtKeys in both collections (debug)                               |
| `help [cmd]`               | Show help. Also `<cmd> help` or `<cmd> --help`                               |
| `quit`                     | Exit the app                                                                 |

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
