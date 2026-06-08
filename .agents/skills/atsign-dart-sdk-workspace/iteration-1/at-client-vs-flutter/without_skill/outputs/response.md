# Difference Between `at_client` and `at_client_flutter`

## Overview

Both `at_client` and `at_client_flutter` are Dart packages in the atSign (atsign.com) ecosystem that provide access to the atProtocol. The key difference lies in their intended runtime environment and the additional platform-specific capabilities each one provides.

---

## `at_client`

`at_client` is the **core, platform-agnostic Dart library** for interacting with the atProtocol. It is designed to work in any Dart environment, including:

- Pure Dart command-line applications
- Server-side Dart programs
- Dart scripts and tooling
- Non-Flutter environments

### Key characteristics

- Provides the fundamental `AtClient` API for CRUD operations on atKeys (put, get, delete, scan)
- Handles atSign authentication and onboarding flows
- Manages connectivity to a secondary (atServer)
- Supports notifications and synchronization between the local keystore and the remote atServer
- Uses Hive as the local key-value store for offline persistence
- Does not depend on Flutter or any Flutter-specific APIs
- Suitable for headless or server environments

---

## `at_client_flutter`

`at_client_flutter` is a **Flutter-specific wrapper** built on top of `at_client`. It adds Flutter-oriented utilities and widgets that make it easier to integrate the atProtocol into a Flutter mobile or desktop application.

### Key characteristics

- Depends on `at_client` (re-exports its API)
- Adds Flutter-specific lifecycle management (e.g., responding to app foreground/background transitions via `WidgetsBindingObserver`)
- Provides helper widgets or services for initialising the atClient within a Flutter widget tree
- May include utilities for handling platform-specific secure storage, biometric authentication prompts, or UI state tied to atSign connection status
- Designed for use in Flutter apps targeting Android, iOS, Web, macOS, Windows, or Linux via Flutter

---

## Summary Table

| Feature | `at_client` | `at_client_flutter` |
|---|---|---|
| Runtime | Any Dart environment | Flutter apps only |
| Core atProtocol API | Yes | Yes (via dependency) |
| Flutter lifecycle hooks | No | Yes |
| Flutter widgets/services | No | Yes |
| Depends on Flutter SDK | No | Yes |
| Use in CLI/server apps | Yes | Not recommended |
| Use in Flutter mobile/desktop apps | Possible but inconvenient | Yes (recommended) |

---

## When to Use Which

- **Use `at_client`** when building a Dart CLI tool, a server-side application, a background service, or any non-Flutter project that needs to interact with the atProtocol.
- **Use `at_client_flutter`** when building a Flutter application (mobile, desktop, or web). It provides the same core functionality as `at_client` plus the Flutter-specific plumbing needed for a smooth integration into the Flutter widget lifecycle.

---

## Note on Accuracy

This answer is based on general knowledge of the atSign ecosystem as of mid-2025. The exact API surface, widget names, and feature set of each package may differ from what is described above. Always consult the official package pages on [pub.dev](https://pub.dev) (`at_client` and `at_client_flutter`) and the [atsign-foundation GitHub organisation](https://github.com/atsign-foundation) for the most up-to-date and authoritative documentation.
