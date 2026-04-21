# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Package Is

`at_client_examples` demonstrates the `at_client` SDK — a Dart library for the atPlatform, a decentralized end-to-end encrypted data-sharing network. Each atSign (e.g. `@alice`) owns a personal server (atServer); the SDK handles key management, encryption, and sync.

This package has no tests of its own. Tests live in `../test/` (the parent `at_client` package).

## Commands

```bash
# Install dependencies
dart pub get

# Static analysis
dart analyze

# Run an example (sender side)
dart run bin/collections_primitives.dart --role sender --other-at-signs @recipient

# Run an example (receiver side)
dart run bin/collections_primitives.dart --role receiver --other-at-signs @sender

# Run parent package tests
cd .. && dart test --concurrency=1

# Run a single parent package test
cd .. && dart test test/<file>_test.dart
```

## Architecture

### Core Abstractions

**`AtClient`** — the main SDK entry point. Obtained via `AtClientManager.getInstance().atClient` after initialization. Handles key-value operations (get/put/delete/notify), encryption, and sync with the atServer.

**`AtCollection<T>`** — higher-level API layered on AtClient for sharing typed collections with other atSigns. Items expire by default after a configurable TTL. Supports read receipts and event streams.

**`CItem<T>`** — wrapper around a collection item; holds value, metadata (TTL, expiry, read receipt), and the atSign it's shared with/from.

### Initialization Pattern

All examples share a common init flow in `lib/init_example_context.dart`:
1. Parse CLI args (`--role sender|receiver`, `--other-at-signs @bob,@alice`, `--root-domain`, etc.)
2. Call `CLIBase` (from `at_cli_commons`) to authenticate and get an `AtClient` instance
3. Return an `ExampleContext` struct holding the client, own atSign, and peer atSigns

### Example Structure (`bin/`)

| File | Demonstrates |
|------|-------------|
| `collections_primitives.dart` | String/Map collections |
| `collections_domain_objects.dart` | Custom serializable objects |
| `collections_generic.dart` | Polymorphic objects (Dog/Cat as Pet) |
| `collections_binary.dart` | `Uint8List` binary data |
| `collections_todos.dart` | Full interactive terminal app (uses `nocterm`) |
| `notifications.dart` | Fire-and-forget via `NotificationService` |
| `rpcs.dart` | RPC-style method invocation between atSigns |

### Serialization Contract

Domain objects (`lib/domain_objects.dart`) must implement `toJson()` / `fromJson()`. Generic collections additionally require registering a type factory so `AtCollection` can deserialize polymorphic types (see `collections_generic.dart`).

### Key Dependency Overrides

`pubspec.yaml` overrides `at_client`, `at_cli_commons`, and `at_commons` to local paths. When upgrading these dependencies, update both the `dependencies` section and the `dependency_overrides` section.
