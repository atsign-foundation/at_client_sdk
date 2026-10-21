# location_sharing — Flutter reference app for `AtCollection<T>`

A small Flutter app that shares a live position between two atSigns,
end-to-end encrypted, using `AtCollection<T>` from `at_client`. It's a
companion to the [`todos`](../todos/README.md) example: where `todos` is
the full tour of the API surface, `location_sharing` is the minimal shape
of a one-directional "share a stream of updates with someone" feature —
the pattern behind live location, presence, or any other fast-changing
value one atSign pushes to another.

## Where this fits

- **`AtCollection<T>` API** — full reference: the
  [`at_client` README](../../../at_client/README.md).
- **Flutter onboarding plumbing**: [`at_client_flutter`](../../README.md)
  (keychain storage, `.atKeys` file import, the login dialogs used in
  [`lib/onboarding.dart`](lib/onboarding.dart)).
- **AtCollection testing patterns**:
  [`09-testing-patterns.md`](../../../at_client_skills/skills/at_client_skills-sdk/references/09-testing-patterns.md)
  — [`test/location_sharing_service_test.dart`](test/location_sharing_service_test.dart)
  is a worked example of unit-testing a collection-backed service without a
  running atServer.

## What it demonstrates

| Feature | Where |
|---|---|
| A typed `AtCollection<T>` opened once, injected into a service | `LocationSharingService.openCollection` → `LocationSharingService(shares: ...)` |
| `sharedWith` on `create()` | `startSharingWith()` |
| `updateSharedWith()` / `delete()` to stop a share | `stopSharingWith()` |
| `draft()` + `update()` to push a fresh value onto an existing item | `publishCurrentLocation()` |
| `Query<T>.wherePath` with a typed `PathField` | `$LocationShare.status`, `_activeSharesQuery()` |
| `Query<T>.watch()` feeding a `StreamBuilder` for realtime UI updates | `screens/location_home.dart` |

There's no location plugin here: [`SimulatedLocationProvider`](lib/services/location_provider.dart)
takes a small random walk from a starting point so a demo shows visible
movement without platform permissions. Swap it for a real GPS-backed
`LocationProvider` function in an app that needs actual positions — nothing
else in the example depends on which one it's given.

## Running

### Prerequisites

- Flutter SDK installed (`flutter doctor` should be clean).
- Two registered atSigns, one per side of the demo. Free atSigns at
  [my.noports.com/no-ports-plans](https://my.noports.com/no-ports-plans).

This example ships without generated platform folders (`android/`, `ios/`,
etc.) to keep the diff small. Generate the ones you need before running on
a device or simulator:

```bash
cd packages/at_client_flutter/example/location_sharing
flutter pub get
flutter create --platforms=macos,ios,android .   # pick the platforms you want
flutter run
```

### Demo

1. Run the app on Device A, log in as `@alice`.
2. Run the app on Device B, log in as `@bob`.
3. On A, type `@bob` into "Share with atSign" and tap **Share**. A's
   position starts publishing every 5 seconds.
4. On B, the share appears under "Shared with me" and its position updates
   live as A's `Timer` ticks.
5. On A, tap the stop icon next to `@bob` to end the share; it disappears
   from B's list.

## Source tour

| Path | What lives there |
|---|---|
| `lib/main.dart` | App entry, login screen |
| `lib/onboarding.dart` | Keychain + `.atKeys` file login flows |
| `lib/models/location_share.dart` | `LocationPoint`, `LocationShare`, and the `$LocationShare` typed query fields |
| `lib/services/location_provider.dart` | The `LocationProvider` typedef and `SimulatedLocationProvider` |
| `lib/services/location_sharing_service.dart` | All `AtCollection<LocationShare>` interaction |
| `lib/screens/location_home.dart` | The logged-in screen: start/stop sharing, two live `StreamBuilder` lists |

## Tests

```bash
flutter test
```

- [`test/location_share_test.dart`](test/location_share_test.dart) — model
  JSON round-trips and the `$LocationShare` path-field extractors.
- [`test/location_sharing_service_test.dart`](test/location_sharing_service_test.dart) —
  `LocationSharingService` against a mocked `AtClient`, following the
  testing-patterns guide referenced above.
- [`test/widget_test.dart`](test/widget_test.dart) — login screen smoke test.
