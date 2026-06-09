<!-- verified: at_client ^3.12.0, at_client_flutter ^1.1.2 — update on next minor release -->

# Package Map: Which Packages to Add

All packages are published on pub.dev under the `atsign.org` publisher:
https://pub.dev/publishers/atsign.org/packages

---

## Recommended Packages

### Core — always needed

```yaml
dependencies:
  at_client: ^3.12.0
```

`at_client` is the core Dart SDK. It provides `AtClient`, `AtCollection<T>`, `CItem<T>`,
`Query<T>`, `NotificationService`, `SyncService`, and all collection-related APIs.
Required for every app that uses the atProtocol.

---

### Flutter apps

```yaml
dependencies:
  at_client_flutter: ^1.1.2   # re-exports at_client — one dep is enough
```

`at_client_flutter` re-exports `at_client` in full (`export 'package:at_client/at_client.dart'`),
so a Flutter app only needs this one entry. You do not need to add `at_client` separately.

`at_client_flutter` adds:
- Auth dialogs: `AtSignSelectionDialog`, `PkamDialog`, `CramDialog`, `RegistrarCramDialog`,
  `AtKeysFileDialog`, `ApkamActivationDialog`, `ApkamDialog`
- `KeychainStorage` — device keychain (iOS Keychain, Android Keystore)
- `KeychainAtKeysIo` — read/write keys from the device keychain
- `AtClientPreference`, `AtClientManager` — Flutter-aware client lifecycle
- Flutter extensions on core types (`import 'package:at_client_flutter/extensions.dart'`)

---

### APKAM enrollment / custom auth

```yaml
dependencies:
  at_auth: ^3.1.0
```

`at_auth` provides `AtAuthRequest`, `AuthResponse`, `AtOnboardingRequest`,
`AtEnrollmentResponse`, `RegistrarService`, and `AtRootDomain`. Required if you are
building custom auth flows or using APKAM enrollment outside the dialog helpers.

For standard Flutter apps using the `at_client_flutter` dialogs, `at_auth` is a
transitive dependency — you may not need to add it explicitly.

---

### Raw cryptographic operations

```yaml
dependencies:
  at_chops: ^3.0.0
```

Add `at_chops` only if your app performs direct cryptographic operations (encrypt,
decrypt, sign, verify, hash). Most apps never need this — `AtCollection<T>` and the
auth dialogs handle all necessary cryptography internally.

---

### CLI / headless Dart apps (no Flutter)

```yaml
dependencies:
  at_client: ^3.12.0
  at_cli_commons: ^3.1.0
```

`at_cli_commons` provides helpers for Dart CLI/server apps: flag parsing, key loading,
`AtClient` setup for headless environments. Not needed in Flutter apps.

---

## Packages — NEVER Add

### `at_common_flutter` ⛔

**Deprecated.** The package's own README states it is deprecated in favour of
`at_client_flutter`. Do not add this to any new or existing app. Migrate to
`at_client_flutter` equivalents.

### `at_backupkey_flutter` ⛔

**Deleted.** The package has been removed from the repository. Copy the backup-key
snippet from `packages/at_client_flutter/example/lib/snippets/at_backup_key.dart`
directly into your own app.

### `at_invitation_flutter` ⛔

**Deprecated.** Copy the invitation snippet from
`packages/at_client_flutter/example/lib/snippets/at_invitation.dart`
directly into your own app.

### `at_sync_ui_flutter` / `at_theme_flutter` ⛔

**Deprecated.** Both packages are being removed. Do not use in new projects.

---

## Packages — Avoid for New Projects (In Migration)

These packages are still published but are in the process of being deprecated.
Their functionality will eventually move into example application code.

| Package | In-migration status |
|---------|-------------------|
| `at_chat_flutter` | Migration in progress |
| `at_contacts_flutter` | Migration in progress |
| `at_contacts_group_flutter` | Migration in progress |
| `at_events_flutter` | Migration in progress |
| `at_follows_flutter` | Migration in progress |
| `at_location_flutter` | Migration in progress |
| `at_notify_flutter` | Migration in progress |
| `at_login_flutter` | Minimal / not fully published |

**Recommendation:** Browse the source of these packages for implementation ideas,
then implement the functionality directly in your app rather than taking a dependency
on packages mid-migration.

---

## Supporting / Utility Packages (usually transitive)

These are typically pulled in as transitive dependencies. You only need to pin them
directly if you're using their types directly in your own API.

| Package | Version | When to pin explicitly |
|---------|---------|----------------------|
| `at_commons` | `^5.10.0` | If you use `AtKey`, `AtMetadata`, `Atsign` directly |
| `at_utils` | `^3.4.0` | If you use `AtSignLogger` directly |
| `at_lookup` | `^3.5.0` | Rarely needed; low-level verb implementation |

---

## Quick Checklists

### Dart CLI / server app

```yaml
dependencies:
  at_client: ^3.12.0
  at_cli_commons: ^3.1.0
  at_auth: ^3.1.0         # for AtAuthRequest if needed
```

### Flutter mobile / desktop app

```yaml
dependencies:
  at_client_flutter: ^1.1.2   # re-exports at_client — one dep is enough
  at_auth: ^3.1.0              # if using RegistrarService or custom APKAM flows
  path_provider: ^2.0.0        # for getApplicationSupportDirectory()
```

### Full imports for a Flutter app

```dart
import 'package:at_client_flutter/at_client_flutter.dart';  // includes all of at_client
import 'package:at_client_flutter/extensions.dart';          // .toAtsign(), etc.
import 'package:at_auth/at_auth.dart';
```
