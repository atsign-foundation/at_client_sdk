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
- `RegistrarService` — the registrar client CRAM onboarding needs
- Flutter extensions on core types
  (`import 'package:at_client_flutter/extensions.dart'`)

---

### APKAM enrollment / custom auth

No extra package. Onboarding, login and enrollment are verbs on `Atsign` in
`at_client` (`open`, `activate`, `enroll`, `resumeEnrollment`), re-exported by
both platform packages, and the approving side is `client.enrollments`; see
[15-client-lifecycle.md](15-client-lifecycle.md). An app building its own UI
calls those; a Flutter app uses the dialogs, a CLI program `CLIBase`. **Do not
add `at_auth`**: it is the protocol layer under `at_client`, and its 4.0
removed the request and response types apps used to hold. What an app needs
for onboarding comes through its platform package.

`AtRootDomain` comes from `at_commons`, surfaced via `at_client`.

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
- `createAtClient(atSign:, atKeysFilePath:, ...)` — the client at_activate's
  commands open: from the keyfile, syncing nothing, on a store of its own
- `lookUpsFor(rootDomain)` — the `lookUps:` `CLIBase` uses: `proxyLookUps()`
  for a root domain of the form `proxy:host:port`, `secureSocketLookUps()`
  otherwise
- `ServiceFactoryWithNoOpSyncService` for stateless no-sync instances
- the `at_activate` and `at_register` executables; `at_register`, and
  `at_activate onboard` without `-c`, send the registrar API key in
  `AT_REGISTRAR_API_KEY` when it is set, and otherwise a built-in key
  (`dart pub global activate at_client_cli`)

Not needed in Flutter apps. It replaces `at_cli_commons` and
`at_onboarding_cli`, whose last majors are deprecated re-exports of it.

---

### Add-ons released on their own schedule

The feature packages an app may add beside its platform package —
`at_contact`, `at_policy`, `at_telemetry`, and `noports_core` (below) — are
released separately from the SDK, so after an SDK major release one may lag
behind for a while. **Check that an add-on resolves before building on it:**
its pub.dev release must depend on the same at_client major as your platform
package — look at the dependencies on its pub.dev page, don't assume.

- On an older major: `dart pub add` fails with "version solving failed"
  naming at_client. Don't work around it with a git dependency,
  `dependency_overrides`, or by pinning the SDK back. Use an alternative
  until the add-on is released, and tell the developer it is waiting on that
  package's release.
- On the same major: the failure comes from the app's own pubspec — an old
  constraint or a stale lockfile. `dart pub outdated` shows which.

---

### Zero-open-port TCP tunnels

NoPorts creates end-to-end encrypted TCP tunnels through the Atsign Platform
with **no open listening ports** on either side — no firewall changes needed
to reach a remote device. Docs: <https://docs.noports.com/>. Use it only when
the app needs raw TCP/socket connectivity to remote machines; ordinary data
exchange belongs in `AtCollection<T>` / notifications.

**Most developers use the NoPorts programs, not a library.** `noports_core`
is the shared library the NoPorts suite is built from — the `npt`, `sshnp`
and `sshnpd` binaries and the NoPorts desktop app. Running a tunnel, or
reaching a device, is a matter of installing and running those programs.

Depend on `noports_core` only to drive tunnels from your own Dart code (the
`Npt` interface) or to write a policy manager (below):

```sh
dart pub add noports_core
```

**Check that it resolves before building on it** — see
[Add-ons released on their own schedule](#add-ons-released-on-their-own-schedule).
While its pub.dev release is on an older at_client major, the alternative is
the NoPorts programs.

**NoPorts has its own access control**, separate from anything else in this
skill — a device daemon decides which client atsigns may reach it, and that is
daemon-side configuration rather than anything your Dart app sets. Sharing,
collection permissions and enrolment namespaces do not govern it. The daemon
takes a static allow list (`--managers`) and/or a `--policy-manager` atsign
asked per request; at least one is required, and when both are given the
policy manager decides for atsigns absent from the list.

If a static list is not enough, `package:noports_core/npa.dart` is the
extension point: implement `NPARequestHandler.doAuthCheck`, which is handed
the daemon atsign, device name, device group and client atsign, and return a
decision. `NPAImpl` runs it as an [`AtRpcCallbacks`](13-rpc.md) service, so
writing a policy manager is an ordinary `AtRpc` responder. The rest lives in
`noports_core` and the NoPorts docs.

---

### Streaming

`at_stream` has no released version yet, so don't add it. For continuous
updates, use `notificationService.subscribe()` or a collection `watch()`.

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

**Deprecated.** Their latest releases only re-export `at_client_cli`. Add
`at_client_cli` instead. Their
`AtOnboardingService`, `AtOnboardingPreference` and `OnboardingUtil` are
gone, and `createAtClient` comes from `at_client_cli` unchanged; see
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

## Packages Under the Platform Package (never added by an app)

`at_client`, `at_auth`, `at_commons`, `at_chops`, `at_lookup` and `at_utils`
are the layers under the platform package. They arrive as transitive
dependencies; an app never adds or imports one. Everything an app needs —
`AtKey`, `Metadata`, `Atsign`, `AtSignLogger`, the storage backends — comes
through the platform package. Cryptography included: `AtCollection<T>`, the
notification service and the auth flows encrypt, sign and verify for the app.

If an app genuinely cannot do something without one of these imports, that is
an SDK gap, not a reason to add the package: report it as a bug.

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
# at_client_flutter re-exports at_client's API — one dep is enough
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
