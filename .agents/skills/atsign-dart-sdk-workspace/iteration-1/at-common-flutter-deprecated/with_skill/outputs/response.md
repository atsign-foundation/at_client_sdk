# Do Not Use `at_common_flutter` in New Flutter Apps

**No, you should not use `at_common_flutter` in your new Flutter app.** The package is officially deprecated. Its own README states it is *"Deprecated in favour of `at_client_flutter`."*

---

## What to Use Instead

For any new Flutter app using the atProtocol, the correct dependencies are:

```yaml
dependencies:
  at_client: ^3.12.0
  at_client_flutter: ^1.1.2
  at_auth: ^3.1.0          # if using RegistrarService or custom APKAM flows
  path_provider: ^2.0.0    # for getApplicationSupportDirectory()
```

`at_client_flutter` is the direct replacement for `at_common_flutter`. It provides everything you need for a Flutter app:

- Auth dialogs: `AtSignSelectionDialog`, `PkamDialog`, `CramDialog`, `RegistrarCramDialog`, `AtKeysFileDialog`, `ApkamActivationDialog`, `ApkamDialog`
- `KeychainStorage` — device keychain (iOS Keychain, Android Keystore)
- `KeychainAtKeysIo` — read/write keys from the device keychain
- `AtClientPreference`, `AtClientManager` — Flutter-aware client lifecycle
- Flutter extensions on core types (`import 'package:at_client_flutter/extensions.dart'`)

---

## Full Import Set for a Flutter App

```dart
import 'package:at_client/at_client.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/extensions.dart';  // .toAtsign(), etc.
import 'package:at_auth/at_auth.dart';
```

---

## Why It Matters

`at_common_flutter` is a hard "never add" — not just discouraged. Do not add it to `pubspec.yaml` in any new or existing project. If you have existing code that depends on it, migrate to `at_client_flutter` equivalents.

The same rule applies to `at_backupkey_flutter`, which is also deprecated. Instead of depending on that package, look at its source code for the backup-key implementation pattern and copy the relevant code directly into your own app.

---

## Summary

| Package | Status | Action |
|---------|--------|--------|
| `at_common_flutter` | Deprecated | Do not use — replace with `at_client_flutter` |
| `at_backupkey_flutter` | Deprecated | Do not use — copy pattern from source into your app |
| `at_client_flutter` | Current | Use this for all Flutter apps |
| `at_client` | Current | Always required |
