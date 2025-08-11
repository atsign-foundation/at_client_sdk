<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_location_flutter)](https://pub.dev/packages/at_location_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Overview

The at_location_flutter package is for Flutter developers who want to implement location feature in their apps. This package provides the feature to share and receive location between two atsigns.

This open source package is written in Dart, supports Flutter and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity
- Share locations and view them on map

We call giving people control of access to their data “flipping the internet”
and you can learn more about how it works by reading this [overview](https://atsign.dev/docs/overview/).

## Get Started:

There are three options to get started using this package.

### 1. Quick start - generate a skeleton app with at_app
This package includes a working sample application in the [Example](https://github.com/atsign-foundation/at_widgets/tree/trunk/at_location_flutter/example) directory that you can use to create a personalized
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

Instructions on how to manually add this package to you project can be found on pub.dev [here](https://pub.dev/packages/at_location_flutter/install).

## How it works

### Setup

### Initialising:
It is expected that the app will first authenticate an atsign using the Onboarding widget.

The location service needs to be initialised with a required GlobalKey<NavigatorState> parameter for navigation purpose (make sure the key is passed to the parent [MaterialApp]), the rest being optional parameters.

```dart
await initializeLocationService(
      navKey,
      mapKey: 'xxxx',
      apiKey: 'xxxx',
      showDialogBox: true,
      streamAlternative: (__){},
      isEventInUse: true, 
    );
```

As this package needs location permission, so add these for:

IOS: (ios/Runner/Info.plist)

```
<key>NSLocationWhenInUseUsageDescription</key>
<string>Explain the description here.</string>
```

Android: (android/app/src/main/AndroidManifest.xml)

```
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### Usage

To share location with an atsign for 30 minutes:
```
sendShareLocationNotification(receiver, 30);
```

To request location from an atsign:
```
sendRequestLocationNotification(receiver);
```

To view location of atsigns:
```
AtLocationFlutterPlugin(
  ['atsign1', 'atsign2', ...]
)
```

To use the default map view:
```
Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => MapScreen(
                currentAtSign: AtLocationNotificationListener().currentAtSign,
                userListenerKeyword: locationNotificationModel,
              )),
    );
```

To use the default home screen view:
```
Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => HomeScreen(),
    ));
```

Different datatypes used in the package:
```
 - LocationNotificationModel: Contains the details of a share/request location and is sent to atsigns while sharing / requesting.
 - LocationDataModel: Gets transferred in the background, contains the actual geo-coordinates and other details.
 - KeyLocationModel - The package uses this to keep a track of all the share/request notifications.
```

### Steps to get mapKey

  - Go to https://cloud.maptiler.com/maps/streets/
  - Click on `sign in` or `create a free account`
  - Come back to https://cloud.maptiler.com/maps/streets/ if not redirected automatically
  - Get your key from your `Embeddable viewer` input text box 
    - Eg : https://api.maptiler.com/maps/streets/?key=<YOUR_MAP_KEY>#-0.1/-2.80318/-38.08702
  - Copy <YOUR_MAP_KEY> and use it.

### Steps to get apiKey

  - Go to https://developer.here.com/tutorials/getting-here-credentials/ and follow the steps


## Example

We have a good example with explanation in the [at_location_flutter](https://pub.dev/packages/at_location_flutter/example) package.

## Open source usage and contributions
This is  open source code, so feel free to use it as is, suggest changes or 
enhancements or create your own version. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
