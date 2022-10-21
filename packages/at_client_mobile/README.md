<img width=250px src="https://atsign.dev/assets/img/atPlatform_logo_gray.svg?sanitize=true">


[![pub package](https://img.shields.io/pub/v/at_client_mobile)](https://pub.dev/packages/at_client_mobile) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client_mobile/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client_mobile/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client_mobile

### Introduction

A Flutter extension to the at_client library which adds support for mobile, desktop, and IoT devices.

SDK that provides the essential methods for building an app using [The atProtocol](https://atsign.com/flip-the-internet/). You may also want to look at [at_client](https://pub.dev/packages/at_client).

**at_client_mobile** package is written in Dart, supports Flutter, and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity

We call giving people control of access to their data "*flipping the internet*".

## Get Started

To get a basic overview of the SDK, please visit the [atsign dococumentation](https://docs.atsign.com/sdk/).

> To use this package, you need to have a basic setup. Visit our documentation to [get started](https://docs.atsign.com/start/).

For more information on how to use this package, visit the [at_client_mobile installation tab](https://pub.dev/packages/at_client_mobile/install).

## Usage

- Get `KeyChainManager` instance to manage your keys while switching between atSigns.

```dart
import 'package:at_client_mobile/at_client_mobile.dart';

static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

/// Fetch atsign from the keychain manager
String atSign = await _keyChainManager.getAtSign();
```

- Delete atSign from the keychain manager

```dart
await _keyChainManager.deleteAtSignFromKeychain(atsign);
```

- Fetch List of atSigns from the keychain manager.

```dart
List<String>? atSignsList = await _keyChainManager.getAtSignListFromKeychain();
```

- Make an atSign primary in device storage.

```dart
AtClientManager.getInstance().setCurrentAtSign(atsign, AppConstants.appNamespace, AtClientPreference());

bool isAtsignSetPrimary = await _keyChainManager.makeAtSignPrimary(atsign);

print(isAtsignSetPrimary); // Prints true if set primary.
```

- Get atSign status from device storage.

```dart
Map<String, bool?> atSignsWithState = await _keyChainManager.getAtsignsWithStatus();

print(atSignsWithState); // Prints a map of atSigns with their status.

/// Output:
/// {
///   "@atSign1": true, // atSign1 is set as primary
///   "@atSign2": false,
///   "@atSign3": false
/// }
```

- Reset atSigns from device storage.

```dart
for (String atsign in atSignsList) {
    await _keyChainManager.resetAtSignFromKeychain(atsign);
}
```

- Get `AtClientService` instance to manage your atSigns.
> `OnboardingWidgetService` is used to onboard your atSigns. Ckeck out the [at_onboarding_flutter](https://pub.dev/packages/at_onboarding_flutter) for more details.

```dart
Map<String?, AtClientService> atClientServiceMap = {};

/// Onboarding widget
OnboardingWidgetService().onboarding(
    fistTimeAuthNextScreen: FirstTimeScreen(),
    nextScreen: null,
    atsign: myAtSign,
    onboard: (value, atsign) async {
        atClientServiceMap = value;
    //... YOUR CODE ...//
    },
    onError: (error) {
        print(error);
    },
);
```

- Remove an atSign from the AtClientService.

```dart
await _keyChainManager.deleteAtSignFromKeychain(atsign);
atClientServiceMap.remove(atsign);
```

- Check if an atSign is onboarded.

```dart
bool isOnboarded = atClientServiceMap.containsKey(atsign);
print(isOnboarded); // Prints true if onboarded.
```

- Format of the .env file

```yaml
NAMESPACE = "at_client_demo"
ROOT_DOMAIN = "root.atsign.org"
```

- Adding the .env file to pubspec.yaml

```yaml
flutter:
  assets: 
    - .env
```

- If your app supports windows platform then add `biometric_storage` in app's dependencies

```
dependencies:
 biometric_storage: ^4.1.3
```

## Example

We have a good example with explanation in the [at_client_mobile](https://pub.dev/packages/at_client_mobile/example) package.
