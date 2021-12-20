<img width=250px src="https://atsign.dev/assets/img/@platform_logo_grey.svg?sanitize=true">

## Now for some internet optimism.

[![pub package](https://img.shields.io/pub/v/at_client_mobile)](https://pub.dev/packages/at_client_mobile) [![pub points](https://badges.bar/at_client_mobile/pub%20points)](https://pub.dev/packages/at_client_mobile/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client_mobile

### Introduction

A Flutter extension to the at_client library which adds support for mobile, desktop and IoT devices.

SDK that provides the essential methods for building an app using [The @protocol](https://atsign.com). You may also want to look at [at_client](https://pub.dev/packages/at_client).

**at_client_mobile** package is written in Dart, supports Flutter and follows the
@platform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity

We call giving people control of access to their data "*flipping the internet*".

## Get Started

Initially to get a basic overview of the SDK, you must read the [atsign docs](https://atsign.dev/docs/overview/).

> To use this package you must be having a basic setup, Follow here to [get started](https://atsign.dev/docs/get-started/setup-your-env/).

Check how to use this package in the [at_client_mobile installation tab](https://pub.dev/packages/at_client_mobile/install).

## Usage

- Get `KeyChainManager` instance to manage your keys while switching between atsigns.

```dart
import 'package:at_client_mobile/at_client_mobile.dart';

static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

/// Fetch atsign from the keychain manager
String atSign = await _keyChainManager.getAtSign();
```

- Delete atsign from the keychain manager

```dart
await _keyChainManager.deleteAtSignFromKeychain(atsign);
```

- Fetch List of atsigns from the keychain manager.

```dart
List<String>? atSignsList = await _keyChainManager.getAtSignListFromKeychain();
```

- Make an atsign primary in device storage.

```dart
AtClientManager.getInstance().setCurrentAtSign(atsign, AppConstants.appNamespace, AtClientPreference());

bool isAtsignSetPrimary = await _keyChainManager.makeAtSignPrimary(atsign);

print(isAtsignSetPrimary); // Prints true if set primary.
```

- Get atsign status from device storage.

```dart
Map<String, bool?> atSignsWithState = await _keyChainManager.getAtsignsWithStatus();

print(atSignsWithState); // Prints a map of atsigns with their status.

/// Output:
/// {
///   "@atsign1": true, // @atsign1 is set as primary
///   "@atsign2": false,
///   "@atsign3": false
/// }
```

- Reset atsigns from device storage.

```dart
for (String atsign in atSignsList) {
    await _keyChainManager.resetAtSignFromKeychain(atsign);
}
```

- Get `AtClientService` instance to manage your atsigns.
> `OnboardingWidgetService` is used to onboard your atsigns. Ckeck out the [at_onboarding_flutter](https://pub.dev/packages/at_onboarding_flutter) for more details.

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

- Remove an AtSign from the AtClientService.

```dart
await _keyChainManager.deleteAtSignFromKeychain(atsign);
atClientServiceMap.remove(atsign);
```

- Check if an atSign is onboarded.

```dart
bool isOnboarded = atClientServiceMap.containsKey(atsign);
print(isOnboarded); // Prints true if onboarded.
```