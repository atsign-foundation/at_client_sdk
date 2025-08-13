<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>


[![pub package](https://img.shields.io/pub/v/at_notify_flutter)](https://pub.dev/packages/at_notify_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Overview

The at_notify_flutter package is for Flutter developers who want to handle notifications in atProtocol apps.

This open source package is written in Dart, supports Flutter and follows the atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity
- Send and receive notifications

We call giving people control of access to their data “flipping the internet” and you can learn more about how it works by reading this
[overview](https://atsign.dev/docs/overview/).

## Get started
There are three options to get started using this package.

### 1. Quick start - generate a skeleton app with at_app
This package includes a working sample application in the [Example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_notify_flutter/example) directory that you can use to create a personalized copy using ```at_app create``` in four commands.

```sh
$ flutter pub global activate at_app 
$ at_app create --sample=<package ID> <app name> 
$ cd <app name>
$ flutter run
```
Notes: 
1. You only need to run ```flutter pub global activate``` once
2. Use ```at_app.bat``` for Windows


### 2. Clone it from GitHub
<!---
Make sure to edit the link below to refer to your package repo.
-->
Feel free to fork a copy the source from the [GitHub repo](https://github.com/atsign-foundation/at_widgets). The example code contained there is the same as the template that is used by at_app above.

```sh
$ git clone https://github.com/atsign-foundation/at_widgets.git
```

### 3. Manually add the package to a project

Instructions on how to manually add this package to you project can be found on pub.dev [here](https://pub.dev/packages/at_notify_flutter/install).

## Get Started:

Initially to get a basic overview of the SDK, you must read the [atsign docs](https://atsign.dev/docs/overview/).

> To use this package you must be having a basic setup, Follow here to [get started](https://atsign.dev/docs/get-started/setup-your-env/).


## How it works

### Setup

It is expected that the app will first authenticate an atsign using the Onboarding widget.

The notify service needs to be initialised with a required atClientManager, 
currentAtSign & atClientPreference.

```
initializeNotifyService(
      atClientManager,
      activeAtSign,
      atClientPreference,
    );
```

This package needs local notification permission:

`IOS: (ios/Runner/AppDelegate.swift)`

```
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
}
```

`Android: (android/app/src/main/AndroidManifest.xml)`

```
android:showWhenLocked="true"
android:turnScreenOn="true"
```

### Usage

To notify an atsign with a message:
```
notifyText(
      context,
      currentAtsign,
      receiver,
      message,
    )
```

To see a list of past notifications:
```
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (context) =>
            NotifyScreen(notifyService: NotifyService())),
  );
```

## Open source usage and contributions
This is open source code, so feel free to use it as is, suggest changes or enhancements or create your own version. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
