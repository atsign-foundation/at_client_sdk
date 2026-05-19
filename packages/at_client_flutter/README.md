<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_client_flutter)](https://pub.dev/packages/at_client_flutter) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client_flutter/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client_flutter/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client_flutter

The **Flutter layer** on top of [`at_client`](../at_client). Adds
pre-built onboarding / authentication dialogs, device-keychain storage
for atKeys, and Flutter-specific extensions — so a new Flutter app can
go from "user has an atSign" to "authenticated `AtClient` in hand" with
a few widget calls.

Supports mobile, desktop, and IoT targets via Flutter. **Flutter
web is not supported** — atSign onboarding and key handling rely
on platform plugins (key-chain, file storage) that don't have web
implementations today.

## What's in the box

| Capability                       | API                                                                                                    |
|----------------------------------|--------------------------------------------------------------------------------------------------------|
| Select atSign + root domain      | `AtSignSelectionDialog.show(context)`                                                                  |
| Onboard a new atSign (CRAM)      | `RegistrarCramDialog.show(...)` then `CramDialog.show(...)`                                            |
| Authenticate via `.atKeys` file  | `AtKeysFileDialog.show(...)` then `PkamDialog.show(...)`                                               |
| Authenticate via device keychain | `KeychainStorage()` + `PkamDialog.show(...)`                                                           |
| Enroll a new device via APKAM    | `ApkamActivationDialog.show(...)` (request side) / `ApkamDialog.show(...)` (approve side)              |
| Keychain read / write / delete   | `KeychainStorage` ([`lib/src/keychain/keychain_storage.dart`](lib/src/keychain/keychain_storage.dart)) |
| Flutter helpers on core types    | `import 'package:at_client_flutter/extensions.dart';`                                                  |

## Examples

The authoritative, end-to-end walkthroughs live in this package's
example app. Read these rather than copying snippets from here:

- [`example/lib/walkthrough.dart`](example/lib/walkthrough.dart) — all
  four authentication / onboarding flows (CRAM onboarding, atKeys-file
  login, keychain login, APKAM enrollment) with the post-auth
  `AtClient` initialization. If you only read one file, read this one.
- [`example/lib/apkam_example.dart`](example/lib/apkam_example.dart) —
  the approve/deny side of APKAM (e.g. a "manager" device approving a
  new phone's enrollment request).
- [`example/lib/main.dart`](example/lib/main.dart) — minimal host app
  wiring the two flows above into navigation.

For a **full Flutter app** using `at_client_flutter` in anger, see
the two flagship examples — deliberately positioned side-by-side
to make a fundamental SDK trade-off visible:

### todos — the idiomatic `AtCollection<T>` Flutter app

[`examples/todos/`](examples/todos/README.md) is the **first
place to look** when building a real Flutter application on the
Atsign Protocol that needs a typed shared **dataset**. It drives
every common collection-shaped pattern through the mobile /
desktop widget stack: typed `AtCollection<T>` with `fromJson` /
`typeTag`, sub-collections (notes per todo), the `Query<T>`
builder with reactive `watch()` / `watchWithSub` / `watchSingle`,
`sharedWith` updates, built-in read receipts, scheduled visibility
via `availableAt`. Wire-compatible with the
[CLI sibling](../at_client/example/README.md#collections--todos-app)
so the same data flows live between TUI and Flutter instances.

Full design, source tour, and multi-device demo in
[`examples/todos/README.md`](examples/todos/README.md).

### dockerstats — live container telemetry

[`examples/dockerstats/`](examples/dockerstats/README.md) is the
canonical worked example of an SDK pattern the API doesn't
impose: **deliver via short-lived notifications, store in a
relational database**. The publisher (a [Dart CLI](../at_client/example/README.md#dockerstats--notification-based-live-telemetry))
emits one `docker stats` sample per container per cycle as a
single `notificationService.send(...)` — no AtCollection, no
keystore writes, no sync queue. The Flutter dashboard subscribes,
persists every sample as-received to a per-atSign **SQLite**
database (no roll-up, no compaction at rest), and renders charts
off that local store with a user-selectable window (5 m → all).
Each window change runs one SQL `GROUP BY` query sized to the
chart's pixel budget, so even an "all" view over years of raw
data stays responsive; live notifications fold into the visible
buckets incrementally.

It exists to demonstrate the trade-off explicitly: mis-applying
`AtCollection<T>` to a high-frequency observation stream — where
query / aggregation / windowing is the dominant design concern —
would be wrong. `AtCollection<T>` is for typed shared *datasets*
(the `todos` example above); notifications + local DB is for
*streams* of observations.

Full design, query-time aggregation semantics, and the seed-DB
workflow for cross-window chart development are in
[`examples/dockerstats/README.md`](examples/dockerstats/README.md).

## Post-authentication initialization

Every auth flow ends the same way: create an `AtClientPreference`, then
call `AtClientManager.setCurrentAtSign(...)` with the `atChops` and
`atLookUp` from the returned `AuthResponse`. The details (chosen
storage directory, namespace, enrollment id) are all in
[`example/lib/walkthrough.dart`](example/lib/walkthrough.dart) in the
`_setupAtClient(...)` function.

## Keychain storage

`KeychainStorage` wraps the device keychain (iOS / Android / macOS /
Windows via `biometric_storage`) and stores atKeys and enrollment data.
The PKAM / APKAM dialogs accept a `KeychainAtKeysIo` instance as a
backup target so successful logins automatically populate the keychain
for next time.

Windows apps additionally need:

```yaml
dependencies:
  biometric_storage: ^4.1.3
```

Direct usage is rare, but when you need it:

```dart
final keychainStorage = KeychainStorage();

AtKeys? alice = await keychainStorage.getAtsign('@alice');
List<String> stored = await keychainStorage.getAllAtsigns();
await keychainStorage.appendAtKeysToKeychain(atKeys);
await keychainStorage.removeAtsignFromKeychain('@alice');
```

## Exporting atKeys

End users **must** back up their master atKeys (see
[at_auth's lifecycle writeup](../at_auth/README.md#phase-2--onboard-the-atsign-generate-the-master-atkeys)).
The keychain → file export:

```dart
final atSign = AtClientManager.getInstance().atClient.getCurrentAtSign()!;
final atKeys = await KeychainStorage().getAtsign(atSign);
if (atKeys == null) throw Exception('No keys found for $atSign');

final atKeysIo = FileAtKeysIo(
  filePath: (_) => '/path/to/${atSign}_key.atKeys',
);
atKeysIo.write(atSign, atKeys);
```

## Where to go next

- [`at_client`](../at_client) — the SDK whose `AtClient` you end up
  with after authentication
- [`at_auth`](../at_auth) — detailed writeup of the atSign
  provisioning / onboarding / APKAM lifecycle, platform-neutral
- [`at_commons`](../at_commons) — `AtKey`, `Metadata`, and friends

## Open source usage and contributions
BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
