<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

## at_location_flutter example
The [at_location_flutter] package is designed to make it easy to share/receive locations between two atsigns and also see it on a map.

### Give it a try
This package includes a working sample application in the [example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_location_flutter/example) directory that demonstrates the key features of the package. To create a personalized copy, use ```at_app create``` as shown below or check it out on GitHub.

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

As the [at_location_flutter] package has to be initialised, so we initialise it in the [init()] of `second_screen.dart` by calling
```dart
    initializeLocationService(
      NavService.navKey,
      mapKey: dotenv.get('MAP_KEY'),
      apiKey: dotenv.get('API_KEY'),
      showDialogBox: true,
    );
```

NOTE: Make sure to pass in the [MAP_KEY] and the [API_KEY] in the `.env` file.

The [second_screen.dart] consists of the following functions:
 - Show maps - Will navigate to the default home screen. If you want to use this functionality then navigate to the [HomeScreen()].
 - Send Location - Sends location for 30 minutes to the typed in atsign. If you want to use this functionality then call [sendShareLocationNotification()], with the receiver atsign as the first parameter and time (in minutes) as the second.
 - Request Location - Requests location from the typed in atsign. If you want to use this functionality then call [sendRequestLocationNotification()], with the receiver atsign as the first parameter.
 - Track Location - Shows the location (if available) of the typed in atsign. If you want to use this functionality then navigate to [AtLocationFlutterPlugin()] and pass in the parameters as needed.
 - Show multiple points - Displays static marker at LatLng(30,45) & LatLng(40,45). If you want to use this functionality then navigate to [showLocation()] and pass in the static geo-coordinates.
 - Notifications: Displays the list of send/received share/request locations. If you want to see the list of notifications then use the [KeyStreamService().atNotificationsStream].

## Open source usage and contributions

Like everything else we do, this package and even the sample application are open source software which means we love it when you gift us with your feedback, contributions and even any bugs that you help us to discover. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
