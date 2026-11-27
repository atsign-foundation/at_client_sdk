---
name: at-client-skills-flutter
description: >
  Use this skill when building or upgrading a Flutter app (mobile, desktop or
  embedded) on the Atsign Platform with at_client_flutter, including from
  at_client_flutter 1.x or the retired at_onboarding_flutter. Covers
  onboarding and login with the at_client_flutter dialogs — CRAM activation of
  a new atsign, an existing .atKeys file, the device keychain, and APKAM
  enrollment of a new device — AtsignFlows for an app with its own UI, where
  the local store lives, logout and switching atsigns, macOS entitlements, and
  holding collection streams and subscriptions in widget state. Use alongside
  at-client-skills-core, which covers collections, notifications, sync, RPC
  and errors.
license: BSD-3-Clause
compatibility: Claude Code and any agentskills.io-compatible agent.
user-invocable: true
metadata:
  version: "2.0.0"
  last_modified: "Fri, 27 Nov 2026 12:38:51 GMT"
---

# Atsign Platform: Flutter

> **Audience:** developers building a Flutter app on the Atsign Platform.

This skill covers what is specific to Flutter: signing in and the widget
lifecycle. What the app does with its client — collections, notifications,
sync, RPC, errors, the lifecycle — is in **at-client-skills-core**; use the
two together. If it is not among your skills, ask the developer to install
it: `dart run skills get --skill at-client-skills-core`.

---

## 1. Rules

- **The package:** `flutter pub add at_client_flutter`, imported as
  `package:at_client_flutter/at_client_flutter.dart`. Its helper library,
  `package:at_client_flutter/extensions.dart`, adds `FileAtKeysIo.getAtsign()`
  and is not in the main import.
- **Where the posture slips:** the dialogs and `AtsignFlows` run at the
  posture of the preference the app hands them; one that names none runs at
  the SDK's default, `legacy`, and says nothing.
- **Upgrading from at_client_flutter 1.x?** `AtAuthRequest`, `AuthService`
  and `FlutterEnrollmentService` are gone: the dialogs hand back the
  `AtClient`. at-client-skills-core's upgrade guide maps each error.
- **Flutter web is not supported** — onboarding and key storage rely on
  platform plugins with no web implementation.

---

## 2. Signing in: four flows, four dialogs

<!-- pyml disable-num-lines 6 md013-->
| Flow | When                                        | Dialogs                                            |
| ---- | ------------------------------------------- | -------------------------------------------------- |
| 1    | A new atsign, first time (CRAM)             | `RegistrarCramDialog` for the secret, `CramDialog` |
| 2    | An existing `.atKeys` file                  | `AtKeysFileDialog`, then `PkamDialog`              |
| 3    | A returning user, keys in the keychain      | `AtSignSelectionDialog`, then `PkamDialog`         |
| 4    | A new device for an existing atsign (APKAM) | `ApkamActivationDialog`                            |

Every dialog hands back the **`AtClient` it opened** (`null` means the user
cancelled or the dialog failed), and the app owns it: it uses it, makes it
current if its screens read the manager, and `stop()`s it when done.

**Flow 2 — the most common for returning developers:**

```dart
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';   // FileAtKeysIo.getAtsign()

final atKeysIo = await AtKeysFileDialog.show(context);          // FileAtKeysIo?
if (atKeysIo == null) return;
final atSign = atKeysIo.getAtsign();
final client = await PkamDialog.show(context,
  atSign: atSign,
  keys: atKeysIo,
  preference: AtClientPreference(posture: PqPosture.pqActive)
    ..namespace = 'my_app'
    ..syncRegex = 'my_app',
  // copies the keys into the keychain for next time
  backupKeys: [KeychainAtKeysIo()],
);
if (client == null) return;
_adopt(client);
```

A `PkamDialog` can come back **offline** — for example for an atsign that
isn't activated yet, or a typo. Read
[references/flutter-auth.md](references/flutter-auth.md) for all four flows in
full, what each client state means, and the shared helpers.

**macOS:** a sandboxed build needs `com.apple.security.network.client` (every
app) and `com.apple.security.files.user-selected.read-only` (to pick a
`.atKeys` file) in **both** `DebugProfile.entitlements` and
`Release.entitlements`; without them the app cannot reach its atServer, or
`AtKeysFileDialog` throws. The keychain needs no entitlement and no signing
team. The reference has the XML.

---

## 3. Storage, adoption and logout

With no `storage`, the dialogs open Hive in the app's support directory
(`getApplicationSupportDirectory()`); pass an `AtClientStorage` only to keep
the store elsewhere or to choose another backend. Likewise `lookUps:`: with
none, they use `secureSocketLookUps()`.

```dart
// An app whose screens read AtClientManager.getInstance().atClient makes the
// client current; an app that passes the client around needs no manager.
void _adopt(AtClient client) => AtClientManager.getInstance().use(client);

// Logout: stop the client. Opening the same atsign again while it is live is
// refused, so every sign-in stops the previous client first.
await client.stop();
```

An app with its own sign-in UI uses `AtsignFlows` instead of the dialogs:
`const AtsignFlows().open(atSign, keys:, preference:)`, and `activate`,
`enroll` and `resumeEnrollment` likewise. Each supplies the storage,
connections and atDirectory finder itself. A pending enrollment's client
takes `storage: await storageOrDefault(atSign, preference)`.

---

## 4. Collections in widgets

Create a `watch()` stream **once** and hold it in `State` (a `late final`
field or `initState`); never call `watch()` inside `build()`, or each rebuild
mints a new stream and drops live updates. Memoise the `Query` and recreate
the stream only when its inputs change, inside the `setState` that changes
them.

```dart
late final Stream<List<CItem<Todo>>> _todos = todos.query().watch();
late StreamSubscription<CItemUpdated> _sub;

@override
void initState() {
  super.initState();
  _sub = todos.updates.listen((_) => setState(() {}));
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

---

## 5. Examples

- [Flutter todos][ex-todos] — the canonical Flutter app; it shares todos with
  the terminal todos app in at_client
- [dockerstats][ex-dockerstats] — notifications + SQLite
- [walkthrough.dart][ex-walkthrough] — the four sign-in flows

[ex-todos]: https://github.com/atsign-foundation/at_client_sdk/tree/trunk/packages/at_client_flutter/example/todos
[ex-dockerstats]: https://github.com/atsign-foundation/at_client_sdk/tree/trunk/packages/at_client_flutter/example/dockerstats
[ex-walkthrough]: https://github.com/atsign-foundation/at_client_sdk/blob/trunk/packages/at_client_flutter/example/lib/walkthrough.dart
