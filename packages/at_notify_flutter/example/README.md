<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

## at_notify_flutter example
The at_notify_flutter package is designed to make it easy to add notifications in atProtocol apps.

### Give it a try
This package includes a working sample application in the [example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_notify_flutter/example) directory that demonstrates the key features of the package. To create a personalized copy, use ```at_app create``` as shown below or check it out on GitHub.

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

We use the `Onboarding()` widget in our `main.dart` and navigate to our `second_screen.dart` after successfully onboarding.

If you want to remove any already paired atsign, use the `Clear paired atsigns` button, it will remove all the paired atsigns for this example package.

The `at_notify_flutter` package has to be initialised.
```dart
    initializeNotifyService(
      atClientManager,
      activeAtSign!,
      atClientPreference,
      rootDomain: AtEnv.rootDomain,
    );
```

The `second_screen.dart` consists of the following functions:
 - atsign - Type in the receiver atsign.
 - Enter message - Type in the message.
 - Notify Text - Send the typed in message to the atsign. If you want to use this functionality then call `notifyText()` with the required parameters.
 - Get past notifications - Navigate to a new screen, to see past notifications of the selected number of days. If you want to use this functionality then navigate to the `NotifyScreen()` screen.


To call notify
```dart
notify(
   context,
   'activeAtSign',
   'toAtSign',
   'message',
);
```

##
Like everything else we do, this package and even the sample application are open source software which means we love it when you gift us with your feedback, contributions and even any bugs that you help us to discover. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
