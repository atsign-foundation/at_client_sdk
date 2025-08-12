<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_events_flutter)](https://pub.dev/packages/at_events_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Overview
The at_events_flutter package is for Flutter developers who would like to integrate event management feature in their apps.

This open source package is written in Dart, supports Flutter and follows the atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity
- Create and update event with location and participants

We call giving people control of access to their data “flipping the internet” and you can learn more about how it works by reading this [overview](https://atsign.dev/docs/overview/).

## Get Started:

There are three options to get started using this package.

### 1. Quick start - generate a skeleton app with at_app
This package includes a working sample application in the
[Example](https://github.com/atsign-foundation/at_widgets/tree/trunk/packages/at_events_flutter/example) directory that you can use to create a personalized copy using ```at_app create``` in four commands.

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

Instructions on how to manually add this package to you project can be found on pub.dev [here](https://pub.dev/packages/at_events_flutter/install).

## How it works

### Setup
### Initialising:
It is expected that the app will first authenticate an atsign using the Onboarding widget.

The event service needs to be initialised with a required GlobalKey<NavigatorState> parameter for navigation purpose (make sure the key is passed to the parent [MaterialApp]), the rest being optional parameters.

```
  initialiseEventService(
    navKey,
    mapKey: 'xxxx',
    apiKey: 'xxxx',
    rootDomain: 'root.atsign.org',
    streamAlternative: (__){},
    initLocation: true,
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

at_events_flutter depends on at_location_flutter for the following features:
 - Sending/receiving location, make sure to initialise at_location_flutter inside/outside the at_events_flutter package, if location sharing is needed.
 - To render the map, pass [mapKey] to [initializeLocationService], if map is needed.
 - To calculate the ETA, pass [apiKey] to [initializeLocationService], if ETA is needed.

### Usage
To create a new event, using the default screen:
```
  CreateEvent(
    AtClientManager.getInstance(),
  ),
```

To use event creation/edit functions, use the [EventService()] singleton, make sure to call [EventService().init()] before using these functions:
- createEvent() - Can create and edit based on [isEventUpdate] passed to [init()]
- editEvent() - Will update the already created event
- sendEventNotification() - Will create a new event

Navigating to the map screen for an event:
```
EventsMapScreenData().moveToEventScreen(eventNotificationModel);
```

Different datatypes used in the package:
```
 - EventNotificationModel: Contains the details of an event and is sent to atsigns while creating an event.
 - EventKeyLocationModel - The package uses this to keep a track of all the event notifications.
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

We have a good example with explanation in the [at_events_flutter](https://pub.dev/packages/at_events_flutter/example) package.


## Open source usage and contributions
This is  open source code, so feel free to use it as is, suggest changes or enhancements or create your own version. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.


