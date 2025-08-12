<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_sync_ui_flutter)](https://pub.dev/packages/at_sync_ui_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Overview
The at_sync_ui_flutter package is for Flutter developers who want to implement the UI indicator for sync process.

This open source package is written in Dart, supports Flutter and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity
- Display visual indicator for sync in progress

We call giving people control of access to their data “flipping the internet”
and you can learn more about how it works by reading this [overview](https://atsign.dev/docs/overview/).

## Get started
There are three options to get started using this package.

### 1. Quick start - generate a skeleton app with at_app
This package includes a working sample application in the
[Example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_sync_ui_flutter/example) directory that you can use to create a personalized
copy using ```at_app create``` in four commands.

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

Feel free to fork a copy of the source from the [GitHub repo](https://github.com/atsign-foundation/at_widgets). The example code contained there is the same as the template that is used by at_app above.

```sh
$ git clone https://github.com/atsign-foundation/at_widgets.git
```

### 3. Manually add the package to a project

Instructions on how to manually add this package to you project can be found on pub.dev [here](https://pub.dev/packages/at_sync_ui_flutter/install).

## How it works

### Setup
### Initialising:
It is expected that the app will first authenticate an atsign using the Onboarding widget.

The `AtSyncUIService` needs to be initialised with a required GlobalKey<NavigatorState> parameter for navigation purpose (make sure the key is passed to the parent [MaterialApp]), the rest being optional parameters.

```dart
    AtSyncUIService().init(
        appNavigator: navKey,
        style: _atSyncUIStyle,
        onSuccessCallback: _onSuccessCallback,
        onErrorCallback: _onErrorCallback,
      );
```

The app can select:

- the style of the UI either `Material` or `Cupertino` by passing the `style` param to [init()] call.
- the type of overlay to be shown while syncing either `Dialog` or `Snackbar` by passing the `atSyncUIOverlay` param to [init()] call.
- the `onSuccessCallback` will be called everytime sync completes with success.
- the `onErrorCallback` will be called everytime sync completes with failure.
- the `primaryColor`, `backgroundColor`, `labelColor` will be used while displaying overlay/snackbar.

### Usage

To call sync and show selected UI:

```dart
    AtSyncUIService().sync(
        atSyncUIOverlay: AtSyncUIOverlay.snackbar,
    );
```

To use listener; can be used to listen to sync status changes:

```dart
    AtSyncUIService().atSyncUIListener
```

### Plugin description
This plugin provides the following material and cuppertino widgets:
- AtSyncButton
- AtSyncIndicator
- AtSyncLinearProgressIndicator
- AtSyncText
- AtSyncDialog
- AtSyncSnackBar

### Sample usage

**AtSyncButton**
```dart
AtSyncButton(
    isLoading: isLoading,
    syncIndicatorColor: Colors.white,
    child: IconButton(
        icon: const Icon(Icons.android),
        onPressed: ...,
    ),
)
```

**AtSyncIndicator**
```dart
AtSyncIndicator(
    value: progress,
    color: _indicatorColor,
)
```

**AtSyncLinearProgressIndicator**
```dart
AtSyncLinearProgressIndicator(
    value: progress,
    color: _indicatorColor,
)
```

**AtSyncText**
```dart
AtSyncText(
    value: progress,
    child: const Text('completed'),
    indicatorColor: _indicatorColor,
)
```

**AtSyncDialog**
```dart
final dialog = material.AtSyncDialog(context: context);
dialog.show(message: 'Downloading ...');
dialog.update(value: _value, message: 'Downloading ...');
dialog.close();
```

**AtSyncSnackBar**
```dart
final snackBar = material.AtSyncSnackBar(context: context);
snackBar.show(message: 'Downloading ...');
snackBar.update(value: _value, message: 'Downloading ...');
snackBar.dismiss();
```

## Example

We have a good example with explanation in the [at_sync_ui_flutter](https://pub.dev/packages/at_sync_ui_flutter/example) package.

## Open source usage and contributions

This is  open source code, so feel free to use it as is, suggest changes or 
enhancements or create your own version. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
