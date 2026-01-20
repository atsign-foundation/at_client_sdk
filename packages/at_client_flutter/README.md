<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>


[![pub package](https://img.shields.io/pub/v/at_client_flutter)](https://pub.dev/packages/at_client_flutter) [![pub points](https://img.shields.io/badge/dynamic/json?url=https://pub.dev/api/packages/at_client_flutter/score&label=pub%20score&query=grantedPoints)](https://pub.dev/packages/at_client_flutter/score) [![build status](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml/badge.svg?branch=trunk)](https://github.com/atsign-foundation/at_client_sdk/actions/workflows/at_client_sdk.yaml) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_client_flutter

### Introduction

A Flutter extension to the at_client library which adds support for mobile, desktop, and IoT devices.

SDK that provides the essential methods for building an app using [The atProtocol](https://atsign.com/flip-the-internet/). You may also want to look at [at_client](https://pub.dev/packages/at_client).

**at_client_flutter** package is written in Dart, supports Flutter, and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity

We call giving people control of access to their data "*flipping the internet*".

## Get Started

> Before using this package for the first time, you should follow the
> [getting started guide](https://docs.atsign.com/)

You may find it useful to read the [atPlatform overview](https://docs.atsign.com/).

This package is available on [pub.dev](https://pub.dev) at https://pub.dev/packages/at_client_flutter

## Usage

See at_client_flutter/example for more details regarding all workflows.

Package provides Flutter Dialogs for the following workflows:
 1. Onboarding via Registrar / Cram
 2. Authentication via File
 3. Authentication via Keychain

#### Atsign / RootDomain Selection Dialog
```
AuthRequest? authRequest = await AtSignSelectionDialog.show(
    context,
);
```

#### Registrar Cram Dialog
```
RegistrarService registrar = RegistrarService("registarURL" "apiKey");
String cramKey = await RegistrarCramDialog.show(
    context,
    atOnboardingRequest,
    registrar: registrar,
);
```

#### Cram Onboarding Dialog
```
AtOnboardingResponse response = await CramDialog.show(
    context, 
    request: onboardingRequest, 
    cramKey: cramKey,
    progressBuilder: progressBuilder,
    onOnboardingComplete: onOnboardingComplete,
    title: title,
    description: description,
);
```

#### Pkam Onboarding Dialog
```
AtAuthRequest request = AtAuthRequest(
    authRequest.atSign,
    atKeysIo: atKeysIo,
    rootDomain: authRequest.rootDomain,
);

AtAuthResponse response = await PkamDialog.show(context, request: request);
```


- If your app supports windows platform then add `biometric_storage` in app's dependencies

```
dependencies:
 biometric_storage: ^4.1.3
```

## Example

More details in the example
`at_client_flutter/example/main.dart`
