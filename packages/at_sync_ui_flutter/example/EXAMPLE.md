<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

## at_sync_ui_flutter example
The [at_sync_ui_flutter] package is designed to make it easy for displaying status of sync process in atProtocol apps.

### Give it a try
This package includes a working sample application in the [example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_sync_ui_flutter/example) directory that demonstrates the key features of the package. To create a personalized copy, use ```at_app create``` as shown below or check it out on GitHub.

```sh
$ flutter pub global activate at_app 
$ at_app create --sample=<package ID> <app name> 
$ cd <app name>
$ flutter run
```
Notes: 
1. You only need to run ```flutter pub global activate``` once
2. Use ```at_app.bat``` for Windows

## How it works

Like most applications built for the atPlatform, we start with the [at_onboarding_flutter](https://pub.dev/packages/at_onboarding_flutter) widget which handles secure management of secret keys for an atsign as cryptographically secure replacement for usernames and passwords.

We use the [Onboarding()] widget in our [main.dart] and navigate to our [second_screen.dart] after successfully onboarding.

If you want to remove any already paired atsign, use the `Clear paired atsigns` button, it will remove all the paired atsigns for this example package.

As the [at_sync_ui_flutter] package has to be initialised, so we initialise it in the [init()] of `second_screen.dart` by calling
```dart
    AtSyncUIService().init(
        appNavigator: NavService.navKey,
        onSuccessCallback: _onSuccessCallback,
        onErrorCallback: _onErrorCallback,
    );
```

The [second_screen.dart] consists of the following functions:
 - Default Sync - Will call the sync function and show the UI selected in the `init()` of `AtSyncUIService()`.
 - Sync with dialog overlay -  Will call the sync function and show the dialog with an overlay. The background will not be responsive.
 - Sync with snackbar - Will call the sync function and show the snackbar with an overlay. The background will be responsive.
 - See all UI options - Will navigate to `UIOptions()` screen which displays all type of UI options available in the package.

## Open source usage and contributions

Like everything else we do, this package and even the sample application are open source software which means we love it when you gift us with your feedback, contributions and even any bugs that you help us to discover. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
