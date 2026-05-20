# location_sharing — collection-backed Flutter example

Flutter example for sharing latest location state with another atSign using
`AtCollection<T>` from `at_client`.

This example is the replacement direction for the old `at_location_flutter`
package: app-owned code, typed collection models, stream-first UI, and no
package-owned map/screens/dialog abstractions.

## What it demonstrates

| Feature | Where |
|---------|-------|
| Typed `AtCollection<LocationShare>` | `lib/services/location_sharing_service.dart` |
| `fromJson` / `toJson` / `typeTag` model shape | `lib/models/location_share.dart` |
| `(owner, id)` item identity | `watchShare(owner, id)` in the service |
| Stream-first state for `StreamBuilder` | `watchSharesSharedWithMe()`, `watchSharesOwnedByMe()`, `watchPublishState()` |
| Stable live subscriptions | The service owns one collection event subscription and refreshes local queries |
| Realtime update visibility | Location tiles pulse and show seconds-level update timestamps |
| Time-limited sharing | `expiresAt` in `startSharingWith(...)` |
| Recipient updates/removal | `stopSharingWith(...)` |

The first implementation slice uses manually-entered coordinates so the
collection pattern is easy to see. Device GPS and map rendering can be layered
on top without changing the collection model.

## Running

```bash
cd packages/at_client_flutter/examples/location_sharing
flutter pub get
flutter run
```

For a multi-atSign demo, run the app as two atSigns. On one device/session,
enter the other atSign and a latitude/longitude, then start sharing. The other
atSign sees the incoming `LocationShare` through a `StreamBuilder`. Publishing
new coordinates should update the existing tile without logging out and back in.

## Source Tour

| Path | Purpose |
|------|---------|
| `lib/main.dart` | Launch screen and onboarding entry points |
| `lib/onboarding.dart` | Keychain, `.atKeys`, and APKAM login flows |
| `lib/models/location_share.dart` | Collection domain model |
| `lib/services/location_sharing_service.dart` | All `AtCollection<T>` interaction |
| `lib/screens/location_home.dart` | StreamBuilder-based UI |
