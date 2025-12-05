Package for onboarding and authentication to an atsign's secondary server  

## Features

- onboard logic - cram authentication,pkam/encryption/apkam key pair generation, initial pkam authentication
- authentication - read keys from .atKeys file, pkam authentication

## Getting started

- Developers should have a free/paid atsign from https://atsign.com/ 

## Usage

Onboard an atsign
```dart
final atAuth = AtAuthCreate();
final atOnboardingRequest = AtOnboardingRequest('@alice')
  ..rootDomain = AtRootDomain('vip.ve.atsign.zone', 64)
  ..appName = 'wavi'
  ..deviceName = 'iphone';
final atOnboardingResponse = await atAuth.onboard(atOnboardingRequest, <cram_secret>);
```

Authenticate an atsign
```dart
final atAuth = AtAuth.create();
final atAuthRequest = AtAuthRequest('@alice')
    ..rootDomain = AtRootDomain('vip.ve.atsign.zone', 64)
    ..atKeysFilePath = args[1];
final atAuthResponse = await atAuth.authenticate(atAuthRequest);
```

## Example

For examples please refer to [examples](https://pub.dev/packages/at_auth/example)
