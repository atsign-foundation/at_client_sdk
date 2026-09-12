<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_client_flutter)](https://pub.dev/packages/at_client_flutter) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client_flutter/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client_flutter/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client_flutter

The **Flutter layer** on top of [`at_client`](../at_client). Adds
pre-built onboarding / authentication dialogs, device-keychain storage
for atKeys, and Flutter-specific extensions — so a new Flutter app can
go from "user has an atSign" to "`AtClient` in hand" with a few widget
calls. One import covers an app:
`package:at_client_flutter/at_client_flutter.dart` re-exports
`at_client`, and nothing here asks an app to import `at_auth`.

Supports mobile, desktop, and IoT targets via Flutter. **Flutter
web is not supported** — atSign onboarding and key handling rely
on platform plugins (key-chain, file storage) that don't have web
implementations today.

## What's in the box

| Capability                       | API                                                                                                    |
|----------------------------------|--------------------------------------------------------------------------------------------------------|
| Select atSign + root domain      | `AtSignSelectionDialog.show(context)` → `AtsignSelection`                                              |
| Onboard a new atSign (CRAM)      | `RegistrarCramDialog.show(...)` then `CramDialog.show(...)` → `AtClient`                               |
| Authenticate via `.atKeys` file  | `AtKeysFileDialog.show(...)` then `PkamDialog.show(...)` → `AtClient`                                  |
| Authenticate via device keychain | `PkamDialog.show(..., keys: KeychainAtKeysIo())` → `AtClient`                                          |
| Enroll a new device via APKAM    | `ApkamActivationDialog.show(...)` → `AtClient` (request side) / `EnrollmentRequestList` (approve side) |
| Manage enrollments               | `client.enrollments` — list, approve, deny, revoke, passcodes (from `at_client`)                       |
| Keychain read / write / delete   | `KeychainStorage` ([`lib/src/keychain/keychain_storage.dart`](lib/src/keychain/keychain_storage.dart)) |
| Flutter helpers on core types    | `import 'package:at_client_flutter/extensions.dart';`                                                  |

## Examples

The authoritative, end-to-end walkthroughs live in this package's
example app. Read these rather than copying snippets from here:

- [`example/lib/walkthrough.dart`](example/lib/walkthrough.dart) — all
  four authentication / onboarding flows (CRAM onboarding, atKeys-file
  login, keychain login, APKAM enrollment), each ending with the
  `AtClient` in hand. If you only read one file, read this one.
- [`example/lib/apkam_example.dart`](example/lib/apkam_example.dart) —
  the approve/deny side of APKAM (e.g. a "manager" device approving a
  new phone's enrollment request), with a simulated requester built on
  `client.enrollments.otp()` and `Atsign.enroll`.
- [`example/lib/main.dart`](example/lib/main.dart) — minimal host app
  wiring the two flows above into navigation.

Smaller copy/paste snippets live under
[`example/lib/snippets`](example/lib/snippets):

- [`example/lib/snippets/at_invitation.dart`](example/lib/snippets/at_invitation.dart)
  — replacement for the deprecated `at_invitation_flutter` package. It keeps
  the SMS/email invite flow as app-owned code instead of a separate Flutter
  package.

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

## Onboarding, provisioning & timeouts

Registering a brand-new atSign and having its atServer **provisioned** are two
separate steps — provisioning can lag registration by anything from seconds to a
few minutes. `CramDialog` (at_client's `Atsign.activate` underneath) handles
that wait for you: it polls for the atServer to come up for **5 minutes** by
default, every 2 seconds. Opening an atSign that already has keys (`PkamDialog`,
`Atsign.open` underneath) instead makes **one bounded connect attempt**, seconds
long, and hands back the client with its `connection` state — online, offline or
refused — because an existing atSign is already provisioned and a dead network
there should surface quickly.

What a Flutter app should do:

1. **Let `CramDialog` wait.** The 5-minute provisioning poll is built in — don't
   wrap your own retry loop around it (that just re-stacks the retries this
   design removed).

2. **Show progress, not a blind spinner.** A multi-minute wait behind an
   indeterminate spinner reads as "hung." `CramDialog` shows each step of the
   activation as it happens; pass `progressBuilder` when the default rendering
   does not fit your design, and it takes over entirely.

3. **When the dialog reports a failure, offer *Retry* rather than a longer
   wait.** In the rare case provisioning runs past 5 minutes, a "Still setting
   up your atSign — tap to keep waiting" button that shows `CramDialog` again
   (a fresh 5-minute poll) beats baking in a 15-minute single timeout that
   makes every genuine failure feel broken.

4. **Returning users go through `PkamDialog`**, which comes back in seconds
   either way. An offline client still serves what it holds locally and reports
   on `client.connection.changes` when the atServer is reached; a refused one
   (revoked, an unapproved enrollment) is the state an app asks the user about.

> **Note:** the activation has no cancellation token, so the 5-minute poll runs
> to completion or timeout even if the user navigates away — a "Cancel" button
> can only change the UI, not abort the in-flight poll. True cancellation is
> tracked in [#2075](https://github.com/atsign-foundation/at_client_sdk/issues/2075).

## The client the dialogs hand back

Every dialog hands back the `AtClient` it opened, and the app owns it: it is the
app's to use and, when it is done, to `stop()`. An app whose screens read
`AtClientManager.getInstance().atClient` makes it current with
`AtClientManager.getInstance().use(client)`; an app that passes the client around
needs no `AtClientManager` at all, and `EnrollmentRequestList` takes an
`atClient` for that case. The details (the chosen storage directory, the
namespace) are all in [`example/lib/walkthrough.dart`](example/lib/walkthrough.dart)
in the `_storage(...)` and `_adopt(...)` functions.

The dialogs take the `AtClientPreference` and, optionally, the `AtClientStorage`
the client opens on; with no storage a Hive store opens under
`preference.hiveStoragePath`.

## Keychain storage

`KeychainStorage` wraps the device keychain (iOS / Android / macOS /
Windows via `biometric_storage`) and stores atKeys. `CramDialog` and
`ApkamActivationDialog` file the keys they mint in the keychain unless given
another `keys` store, and `PkamDialog` takes `backupKeys`, stores the keys are
copied into once the client is open — so a login from a `.atKeys` file
populates the keychain for next time.

`KeychainAtKeysIo` is a full `WrittenAtKeysIo`: as well as `read` and
`write` it implements `flush`, and inherits `update`. That matters because
the post-quantum paths add key material to the store as they run — a
namespace key's private half, the atSign's signing-root private — and on
Flutter this is the *default* store. Use `update` for any addition, never a
hand-rolled `read` → mutate → `flush`; see
[at_auth's note on why](../at_auth/README.md#the-atkeys-file-format).

`write` is create-only, like every other `WrittenAtKeysIo`: it throws
`AtKeysFileOverwriteException` if the atSign already has an entry. To
persist a change to keys that are already stored, use `flush` or `update`.

An enrollment awaiting approval lives in the keys store too, as pending key
material: `ApkamActivationDialog` reads it back and resumes the wait rather
than submitting a second request.

Windows apps additionally need:

```yaml
dependencies:
  biometric_storage: ^5.0.1
```

Direct usage is rare, but when you need it:

```dart
final keychainStorage = KeychainStorage();

AtKeys? alice = await keychainStorage.getAtsign('@alice');
List<String> stored = await keychainStorage.getAllAtsigns();
await keychainStorage.appendAtKeysToKeychain(keys: atKeys);
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

- [`at_client`](../at_client) — the SDK whose `AtClient` the dialogs hand
  back, and whose `Atsign` verbs they run
- [`at_auth`](../at_auth) — the `.atKeys` keyfile format and the registrar
  client
- [`at_commons`](../at_commons) — `AtKey`, `Metadata`, and friends

## Open source usage and contributions
BSD3-licensed. See [`CONTRIBUTING.md`](../../CONTRIBUTING.md) for
guidance on setting up tools, running tests, and raising a PR.
