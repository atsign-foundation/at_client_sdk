# Package Map: Which Packages to Add

All packages are published on pub.dev under the `atsign.org` publisher:
<https://pub.dev/publishers/atsign.org/packages>

---

## Recommended Packages

### One platform package — always needed

An app depends on **one platform package** and imports only its barrel:

| App                                     | Add                 | Import                                             |
| --------------------------------------- | ------------------- | -------------------------------------------------- |
| Dart CLI, daemon, server, Dart on IoT   | `at_client_cli`     | `package:at_client_cli/at_client_cli.dart`         |
| Flutter (mobile, desktop, embedded)     | `at_client_flutter` | `package:at_client_flutter/at_client_flutter.dart` |

Each re-exports at_client's API — `AtClient`, `AtCollection<T>`, `CItem<T>`,
`Query<T>`, `NotificationService`, `SyncService`, the `Atsign` verbs — with
the native pieces (`FileAtKeysIo`, `secureSocketLookUps`,
`CacheableSecondaryAddressFinder`, `HiveAtClientStorage`), and supplies a
working default for everything that differs by platform (storage, transport,
keys, logging). You do not add `at_client` beside it.

`at_client` itself is the platform-neutral **core**: public, but for building
a platform package, or for a program that passes every dependency explicitly.
A browser platform package, `at_client_web`, does not exist yet.

---

### Flutter apps

```sh
dart pub add at_client_flutter   # the one SDK dependency
```

`at_client_flutter` re-exports at_client's native API
(`export 'package:at_client/at_client_io.dart'`), its Hive, SQLite and
in-memory stores and its mixins, so a Flutter app only needs this one entry.

`at_client_flutter` adds:

- Auth dialogs: `AtSignSelectionDialog`, `PkamDialog`, `CramDialog`,
  `RegistrarCramDialog`, `AtKeysFileDialog`, `ApkamActivationDialog`
- `KeychainStorage` — device keychain (iOS Keychain, Android Keystore)
- `KeychainAtKeysIo` — read/write keys from the device keychain
- `RegistrarService` (re-exported from at_auth) — the registrar client CRAM
  onboarding needs
- Flutter extensions on core types
  (`import 'package:at_client_flutter/extensions.dart'`)

---

### APKAM enrollment / custom auth

No extra package. Onboarding, login and enrollment are verbs on `Atsign` in
`at_client` (`open`, `activate`, `enroll`, `resumeEnrollment`), re-exported by
both platform packages, and the approving side is `client.enrollments`; see
[15-client-lifecycle.md](15-client-lifecycle.md). An app building its own UI
calls those; a Flutter app uses the dialogs, a CLI program `CLIBase`. **Do not
add `at_auth`**: it is the protocol layer under `at_client`, its 4.0 removed
the request and response types apps used to hold, and the one type an app may
want from it, `RegistrarService`, is re-exported by both platform packages.

`AtRootDomain` comes from `at_commons`, surfaced via `at_client`.

---

### Raw cryptographic operations

```sh
dart pub add at_chops
```

Add `at_chops` only if your app performs direct cryptographic operations
(encrypt, decrypt, sign, verify, hash). Most apps never need this —
`AtCollection<T>` and the auth dialogs handle all necessary cryptography
internally. at_client 4.0 is on at_chops 3.7, so `dart pub add` picks a 3.x.

---

### CLI / headless Dart apps (no Flutter)

```sh
dart pub add at_client_cli   # the one SDK dependency
```

`at_client_cli` covers every native Dart program that isn't Flutter. Beside
at_client's native API, its Hive, SQLite and in-memory stores and its mixins,
the registrar and the io logging handlers (`StdErrLoggingHandler`, `FileLoggingHandler`, `CLILoggingHandler`),
it provides:

- `CLIBase` — one-line arg parsing + `.atKeys` loading + an online client;
  see [14-multi-agent.md](14-multi-agent.md)
- `CliKeys` — `CliKeys.fileFor(atSign, path:, passPhrase:)` (default
  `~/.atsign/keys/<atSign>_key.atKeys`) and `CliKeys.storageFor(atSign,
  program:, id:, path:)` (default: the store `CLIBase` opens for that
  namespace), for a program that calls the `Atsign` verbs itself
- `lookUpsFor(rootDomain)` — the `lookUps:` `CLIBase` uses: `proxyLookUps()`
  for a root domain of the form `proxy:host:port`, `secureSocketLookUps()`
  otherwise
- `ServiceFactoryWithNoOpSyncService` for stateless no-sync instances
- the `at_activate` and `at_register` executables
  (`dart pub global activate at_client_cli`)

Not needed in Flutter apps. It replaces `at_cli_commons` and
`at_onboarding_cli`, whose last majors are deprecated re-exports of it.

---

### Zero-open-port TCP tunnels

```sh
dart pub add noports_core
```

NoPorts creates end-to-end encrypted TCP tunnels through the Atsign Platform
with **no open listening ports** on either side — no firewall changes needed
to reach a remote device. CLI: the `npt` binary; programmatic: the `Npt`
class. Docs: <https://docs.noports.com/>. Add only when the app needs raw
TCP/socket connectivity to remote machines; ordinary data exchange belongs in
`AtCollection<T>` / notifications.

---

### Streaming (pre-release)

```sh
dart pub add at_stream
```

`at_stream` streams data over the Atsign Platform through Dart's async stream
interfaces. **Pre-release** (`0.1.0-dev.x`) — expect API churn; for most
continuous-update cases, `notificationService.subscribe()` or a collection
`watch()` is the stable choice.

---

## Packages — NEVER Add

### `at_common_flutter` ⛔

**Deprecated.** The package's own README states it is deprecated in favour of
`at_client_flutter`. Do not add this to any new or existing app. Migrate to
`at_client_flutter` equivalents.

### `at_onboarding_flutter` ⛔

**Discontinued.** pub.dev marks this package discontinued and names
`at_client_flutter` as its replacement. Do not add it, and do not reach for it
when a task calls for onboarding, activation, or sign-in — the
`at_client_flutter` auth dialogs (`AtSignSelectionDialog`, `AtKeysFileDialog`,
`ApkamActivationDialog`, `PkamDialog`) cover all of it.

### `at_backupkey_flutter` ⛔

**Deleted.** The package has been removed from the repository. Copy the
backup-key snippet from
`packages/at_client_flutter/example/lib/snippets/at_backup_key.dart`
directly into your own app.

### `at_invitation_flutter` ⛔

**Deprecated.** Use `AtClientInvitations`, which both platform packages
re-export, shown in
`packages/at_client_flutter/example/invitations`.

### `at_sync_ui_flutter` / `at_theme_flutter` ⛔

**Deprecated.** Both packages are being removed. Do not use in new projects.

### `at_cli_commons` / `at_onboarding_cli` ⛔

**Deprecated.** Their last majors, at_cli_commons 4.0.0 and at_onboarding_cli
2.0.0, only re-export `at_client_cli`. Add `at_client_cli` instead. Their
`AtOnboardingService`, `AtOnboardingPreference`, `createAtClient` and
`OnboardingUtil` are gone; see
[01-deprecation-guide.md](01-deprecation-guide.md) for what replaces each.

---

## Packages — Avoid for New Projects (In Migration)

These packages are still published but are in the process of being deprecated.
Their functionality will eventually move into example application code.

| Package | In-migration status |
| --------- | ------------------- |
| `at_chat_flutter` | Migration in progress |
| `at_contacts_flutter` | Migration in progress |
| `at_contacts_group_flutter` | Migration in progress |
| `at_events_flutter` | Migration in progress |
| `at_follows_flutter` | Migration in progress |
| `at_location_flutter` | Migration in progress |
| `at_notify_flutter` | Migration in progress |
| `at_login_flutter` | Minimal / not fully published |

**Recommendation:** Browse the source of these packages for implementation
ideas, then implement the functionality directly in your app rather than taking
a dependency on packages mid-migration.

---

## Supporting / Utility Packages (usually transitive)

These are pulled in as transitive dependencies, and the platform package
re-exports what an app uses of them. Add one directly only for an import the
platform package does not carry.

| Package | When to add it explicitly |
| --------- | ---------------------- |
| `at_commons` | Only for `package:at_commons/at_builders.dart` (the verb builders); `AtKey`, `Metadata` and `Atsign` come through the platform package |
| `at_utils` | Not for `AtSignLogger`, which the platform package re-exports; a `^3.x` constraint cannot resolve beside at_client 4 |
| `at_lookup` | Rarely needed; low-level verb implementation |
| `at_client` | Never in an app: the platform package re-exports all of it, the storage backends and mixins included |

---

## Quick Checklists

### Dart CLI / server app

```sh
dart pub add at_client_cli
# CLIBase, CliKeys and the lifecycle verbs, all from one import
```

### Flutter mobile / desktop app

```sh
dart pub add at_client_flutter
# at_client_flutter re-exports at_client's API (and RegistrarService) — one dep is enough
# add path_provider only to build your own storage under getApplicationSupportDirectory()
```

### Full imports for a CLI program

```dart
import 'package:at_client_cli/at_client_cli.dart';  // all of at_client, CLIBase, CliKeys
```

### Full imports for a Flutter app

```dart
import 'package:at_client_flutter/at_client_flutter.dart';  // includes all of at_client
import 'package:at_client_flutter/extensions.dart';          // FileAtKeysIo.getAtsign(), etc.
```
