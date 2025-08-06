Package for onboarding and authentication to an atsign's secondary server  

## Features

- onboard logic - cram authentication,pkam/encryption/apkam key pair generation, initial pkam authentication
- authentication - read keys from .atKeys file, pkam authentication

## Getting started

- Developers should have a free/paid atsign from https://atsign.com/ 

## Usage

Onboard an atsign
```dart
final atAuth = AtAuthImpl();
final atOnboardingRequest = AtOnboardingRequest('@alice')
  ..rootDomain = 'vip.ve.atsign.zone'
  ..enableEnrollment = true
  ..appName = 'wavi'
  ..deviceName = 'iphone';
final atOnboardingResponse = await atAuth.onboard(atOnboardingRequest, <cram_secret>);
```

Authenticate an atsign
```dart
final atAuth = AtAuthImpl();
final atAuthRequest = AtAuthRequest('@alice')
    ..rootDomain = 'vip.ve.atsign.zone'
    ..atKeysFilePath = args[1];
final atAuthResponse = await atAuth.authenticate(atAuthRequest);
```

## Example

For examples please refer to [examples](https://pub.dev/packages/at_auth/example)