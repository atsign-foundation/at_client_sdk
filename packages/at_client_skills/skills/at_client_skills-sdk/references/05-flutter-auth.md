# Flutter Auth Guide

`at_client_flutter` provides four authentication flows as dialog-based helpers.
Every dialog hands back the **`AtClient` it opened**, or `null` when the user
cancelled or the dialog failed. The app owns that client: it uses it, makes it
current if its screens read `AtClientManager`, and `stop()`s it when done.
Nothing in these flows imports `at_auth`.

## Dependencies

Add the packages with `dart pub add` (pins the latest compatible versions):

```sh
dart pub add at_client_flutter path_provider
# at_client_flutter re-exports at_client; path_provider is for
# getApplicationSupportDirectory()
```

---

## Prerequisite: the atsign must be activated

Before any of these flows can authenticate, the atsign must be **activated** —
its atServer must be registered in the **atDirectory** (the atServer address
registry). Activation happens once, via Flow 1 (CRAM) below or an onboarding
app / the registrar.

Opening an atsign that isn't activated (or a typo) comes back **refused** with
cause `noAtServer`: the atDirectory has no atServer for it. On the first open
of those keys on a device that is a thrown `AtOpenRefusedException`, since
there is nothing local to serve. Activate it first (Flow 1), then Flows 2–4
(existing keys / keychain / APKAM) will resolve it.

---

## Shared helpers (all flows)

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';   // FileAtKeysIo.getAtsign()
import 'package:path_provider/path_provider.dart';

const namespace = 'my_namespace';

AtClientPreference _preference() => AtClientPreference()
  ..namespace = namespace
  ..syncRegex = namespace;   // scope sync to this app (see 11-sync.md)

/// Where this app keeps the atSign's local store. closedByClient: the client
/// closes it when it stops, so there is nothing to tear down.
Future<HiveAtClientStorage> _storage(String atSign) async {
  final dir = await getApplicationSupportDirectory();
  return HiveAtClientStorage(
      atSign: atSign, storagePath: dir.path, closedByClient: true);
}

/// Screens that read AtClientManager.getInstance().atClient need this; an app
/// that passes the client around does not.
void _adopt(AtClient client) => AtClientManager.getInstance().use(client);
```

`AtClientPreference.hiveStoragePath` and `commitLogPath` are deprecated: the
storage object above is where the store lives, and it is what the dialogs and
the `Atsign` verbs take as `storage`.

---

## Flow 1: New atsign — CRAM Activation (first-time only)

Use when a developer wants to activate a brand-new atsign for a user.
Requires a `RegistrarService` (re-exported by `at_client_flutter`) configured
with a registrar URL and API key.

```dart
final registrar = RegistrarService(
  registrarUrl: 'my.atsign.com',
  apiKey: 'your-api-key',        // from the atsign.com developer portal
);

Future<void> activateNewAtSign(BuildContext context) async {
  // Step 1: the user picks / types an atSign and a root domain
  final selection = await AtSignSelectionDialog.show(context);   // AtsignSelection?
  if (selection == null || !context.mounted) return;

  // Step 2: the registrar emails an OTP; the dialog exchanges it for the CRAM key
  final cramKey = await RegistrarCramDialog.show(context, selection.atSign,
      registrar: registrar);
  if (cramKey == null || !context.mounted) return;

  // Step 3: activate. The dialog polls for the atServer to be provisioned
  // (5 minutes, every 2 s), mints the atSign's first keys into the keychain
  // (or `keys:`), opens the client on them and hands it back.
  final client = await CramDialog.show(
    context,
    atSign: selection.atSign,
    rootDomain: selection.rootDomain,
    cramKey: cramKey,
    preference: _preference(),
    storage: await _storage(selection.atSign),
  );
  if (client == null) return;
  _adopt(client);
}
```

Pass `progressBuilder` when the default step-by-step rendering does not fit
your design. Let the dialog wait; do not wrap a retry loop around it. On a
failure offer *Retry* (show the dialog again) rather than a longer wait.

---

## Flow 2: Existing .atKeys File

Use when the user has an `.atKeys` file (typically from a previous device).

```dart
Future<void> loginWithFile(BuildContext context) async {
  // Step 1: the user picks the .atKeys file
  final atKeysIo = await AtKeysFileDialog.show(context);   // FileAtKeysIo?
  if (atKeysIo == null || !context.mounted) return;
  final atSign = atKeysIo.getAtsign();

  // Step 2: open on the file. backupKeys copies the keys into the keychain
  // once the client is open, so the next login can come from the keychain.
  final client = await PkamDialog.show(
    context,
    atSign: atSign,
    keys: atKeysIo,
    preference: _preference(),
    storage: await _storage(atSign),
    backupKeys: [KeychainAtKeysIo()],
  );
  if (client == null) return;
  _adopt(client);
}
```

> **macOS platform setup (required).** A sandboxed macOS build needs two
> entitlements in **both** `macos/Runner/DebugProfile.entitlements` **and**
> `macos/Runner/Release.entitlements`:
>
> ```xml
> <!-- Connect to the atServer (required by every atsign app) -->
> <key>com.apple.security.network.client</key>
> <true/>
> <!-- Pick the .atKeys file via AtKeysFileDialog / file_picker -->
> <key>com.apple.security.files.user-selected.read-only</key>
> <true/>
> ```
>
> Without `network.client` the app cannot reach the atServer at all; without the
> file-access entitlement `AtKeysFileDialog` throws
> `PlatformException(ENTITLEMENT_NOT_FOUND, ...)` when picking the file.
> macOS only — iOS and Android need neither.
>
> Add `com.apple.security.network.server` (to **both** Debug and Release) only
> when the app opens a *listening* socket — e.g. it embeds NoPorts/`npt`
> tunnels, which bind a local port. Plain `at_client` traffic is outbound-only
> and needs just `network.client`. (Flutter's default
> `DebugProfile.entitlements` already includes `network.server` for the debug
> VM service — that alone doesn't mean your app needs it in Release.)

---

## Flow 3: Device Keychain (Returning User)

Use for fast re-login on a device that has already onboarded an atsign.
Reads existing atsigns from the device keychain (iOS Keychain /
Android Keystore).

```dart
Future<void> loginWithKeychain(BuildContext context) async {
  // Step 1: the atSigns already stored on this device
  final atSigns = await KeychainStorage().getAllAtsigns();
  if (atSigns.isEmpty) {
    _showMessage(context, 'No atSigns in keychain. Onboard one first.');
    return;
  }
  if (!context.mounted) return;

  // Step 2: the user picks one
  final selection =
      await AtSignSelectionDialog.show(context, existingAtSigns: atSigns);
  if (selection == null || !context.mounted) return;

  // Step 3: open on the keychain
  final client = await PkamDialog.show(
    context,
    atSign: selection.atSign,
    rootDomain: selection.rootDomain,
    keys: KeychainAtKeysIo(),
    preference: _preference(),
    storage: await _storage(selection.atSign),
  );
  if (client == null) return;
  _adopt(client);
}
```

---

## Flow 4: APKAM — New Device Enrollment

Use when a user wants to add a new device to an existing atsign. A device
already holding the atSign's keys (the "manager") approves the request, from
`client.enrollments` or the `EnrollmentRequestList` widget.

```dart
Future<void> loginWithApkam(BuildContext context) async {
  // Step 1: the user picks the atSign to enroll this device with
  final selection = await AtSignSelectionDialog.show(context);
  if (selection == null || !context.mounted) return;

  // Step 2: the dialog submits the request, waits for the approval, and
  // hands back the client opened on the approved keys. The keys are filed in
  // `keys` (the keychain by default); a request already pending there is
  // resumed rather than submitted again, so a restart mid-wait is fine.
  final client = await ApkamActivationDialog.show(
    context,
    atSign: selection.atSign,
    rootDomain: selection.rootDomain,
    appName: namespace,              // what the manager device sees
    deviceName: 'default',
    namespaces: {namespace: 'rw'},   // the permissions this device needs
    preference: _preference(),
    keys: KeychainAtKeysIo(),
    storage: await _storage(selection.atSign),
  );
  if (client == null) return;
  _adopt(client);
}
```

There is no second `PkamDialog`: the enrolled client is the one handed back.

**The approve side**, on the manager device:

```dart
final pending = await client.enrollments.pending();
await client.enrollments.approve(pending.first.enrollmentId!);   // or deny(id)
client.enrollments.requests.listen((r) => ...);                  // new requests as they arrive
final passcode = await client.enrollments.otp();                 // what the new device types
```

or drop in `EnrollmentRequestList(atClient: client)`, which renders the roster
and decides.

---

## What the client comes back as

`PkamDialog` (Flow 2, 3) and the client Flow 4 hands back are `Atsign.open`
underneath: **one bounded connect attempt**, seconds long, and the client comes
back whether the atServer was reached or not.

```dart
final state = client.connection.current;   // online | offline | refused, with a cause
client.connection.changes.listen((s) => setState(() => _state = s));
```

- **offline** — the client serves its local store and syncs when the atServer
  is reached. A 1.x app treated this as a failed login; a 2.0 app decides, and
  usually shows an indicator rather than blocking.
- **refused** (`revoked`, `unauthenticated`, `invalidEnrollment`,
  `enrollmentNotApproved`) — the atServer rejected the keys. Ask the user.
- A **first** open of these keys on a device that is refused throws
  `AtOpenRefusedException` instead, since nothing is held locally to serve.

See [15-client-lifecycle.md](15-client-lifecycle.md) for the full state model,
the services and the shutdown checklist.

---

## Logout, and switching atsigns

```dart
await client.stop();   // stops sync, notifications and the connection; closes the store
```

Opening the same atSign again while its client is live is refused with a
`StateError`, so every sign-in stops the previous client first. To switch
users: `stop()` the current client, run the flow for the next one, `_adopt`
the client it hands back. `AtClientManager.getInstance().reset()` is a test
hook, not a logout.

---

## Canonical Examples

<!-- pyml disable-num-lines 2 md013-->
- [packages/at_client_flutter/example/lib/walkthrough.dart](../../../../at_client_flutter/example/lib/walkthrough.dart) — all four flows, plus the `_storage` and `_adopt` helpers
- [packages/at_client_flutter/example/lib/apkam_example.dart](../../../../at_client_flutter/example/lib/apkam_example.dart) — the approve/deny side of APKAM
- [packages/at_client_flutter/examples/todos/lib/onboarding.dart](../../../../at_client_flutter/examples/todos/lib/onboarding.dart) — Flows 2 and 3 in a real app

---

## Key Imports

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
// Exports all of at_client plus: AtSignSelectionDialog (→ AtsignSelection),
// PkamDialog, CramDialog, RegistrarCramDialog, AtKeysFileDialog,
// ApkamActivationDialog, EnrollmentRequestList, KeychainStorage,
// KeychainAtKeysIo, and RegistrarService (the one at_auth type an app wants).

import 'package:at_client_flutter/extensions.dart';
// Adds FileAtKeysIo.getAtsign() (used in Flow 2).
// Note: String.toAtsign() comes from at_client, NOT this import.
```

No `import 'package:at_auth/at_auth.dart'`: `AtAuthRequest`, `AuthResponse`,
`AtOnboardingRequest` and `AtEnrollmentResponse` are gone with the services
that took them. `AtRootDomain` comes from `at_commons`, via `at_client`.
