<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_backupkey_flutter)](https://pub.dev/packages/at_backupkey_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Overview
The at_backupkey_flutter package provides the functionality to take backup of secret keys of an onboarded atSign.

This open source package is written in Dart, supports Flutter and follows the
atPlatform's decentralized, edge computing model with the following features: 
- Cryptographic control of data access through personal data stores
- No application backend needed
- End to end encryption where only the data owner has the keys
- Private and surveillance free connectivity

We call giving people control of access to their data “flipping the internet”
and you can learn more about how it works by reading this
[overview](https://atsign.dev/docs/overview/).

## Get started
There are two options to get started using this package.

### 1. Clone it from GitHub
Feel free to fork a copy of the source from the [GitHub repo](https://github.com/atsign-foundation/at_widgets). The example code contained there demonstrates the usage of this package.

```sh
$ git clone https://github.com/atsign-foundation/at_widgets
```

### 2. Manually add the package to a project

Instructions on how to manually add this package to you project can be found on pub.dev [here](https://pub.dev/packages/at_backupkey_flutter/install).

## How it works

Secret keys are generated for an atSign during onboarding flow of atProtocol. This package helps to add those keys in '.atKeys' file. This file can then be saved in the local filesystem or iCloud/Gdrive.

## Setup
The following platform specific setups are required:

### Android
Add android:exported = "true" to activity

```
<activity
            android:name=".MainActivity"
            android:exported="true"
            ...>
```

Add the following permissions to AndroidManifest.xml

```
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
```

Also, the Android version support in app/build.gradle
```
compileSdkVersion 29

minSdkVersion 24
targetSdkVersion 29
```

### iOS
Update the Podfile with the following lines of code:

```
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        ## dart: PermissionGroup.calendar
        'PERMISSION_EVENTS=0',

        ## dart: PermissionGroup.reminders
        'PERMISSION_REMINDERS=0',

        ## dart: PermissionGroup.contacts
        'PERMISSION_CONTACTS=0',

        ## dart: PermissionGroup.microphone
        'PERMISSION_MICROPHONE=0',

        ## dart: PermissionGroup.speech
        'PERMISSION_SPEECH_RECOGNIZER=0',

        ## dart: [PermissionGroup.location, PermissionGroup.locationAlways, PermissionGroup.locationWhenInUse]
        'PERMISSION_LOCATION=0',

        ## dart: PermissionGroup.notification
        'PERMISSION_NOTIFICATIONS=0',

        ## dart: PermissionGroup.sensors
        'PERMISSION_SENSORS=0'
      ]
    end
  end
end
```

### macOS:
Go to your project folder, macOS/Runner/DebugProfile.entitlements
(For release mode, you need to open macOS/Runner/Release.entitlements)

and add the following key:
```
<key>com.apple.security.files.downloads.read-write</key>
<true/>
```

## Open source usage and contributions
This is  open source code, so feel free to use it as is, suggest changes or 
enhancements or create your own version. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) 
for detailed guidance on how to setup tools, tests and make a pull request.
