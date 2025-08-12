<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_onboarding_flutter)](https://pub.dev/packages/at_onboarding_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Overview

This at_onboarding_flutter package handles secure management of secret keys
for authenticating an atsign as cryptographically secure replacement for
usernames and passwords.

This open source package is written in Dart, supports Flutter and follows
the atPlatform's decentralized, edge computing model with the following
features:

- Takes away the difficulty in implementing atsign authentication.
- Generate and Supports free atsigns.
- Supports multiple atSign onboarding.
- Flexibility of either pair atSign with QRCode or Atkey file.
- Reset/Sign out button.

We call giving people control of access to their data “flipping the internet”
and you can learn more about how it works by reading this
[overview](https://atsign.dev/docs/overview/).

## Get Started

There are two options to get started using this package.

### 1. Clone it from GitHub

Feel free to fork a copy the source from the
[GitHub repo](https://github.com/atsign-foundation/at_widgets).
The example code contained there demonstrates the onboarding flow of an atSign.

```sh
git clone https://github.com/atsign-foundation/at_widgets
```

### 2. Manually add the package to a project

Instructions on how to manually add this package to you project can be found
on pub.dev [here](https://pub.dev/packages/at_onboarding_flutter/install).

#### Setup

<details>
<summary>Android</summary>

Add the following permissions to AndroidManifest.xml

```
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" />
    <uses-feature android:name="android.hardware.camera.autofocus" />
    <uses-feature android:name="android.hardware.camera.flash" />
```

Also, the Android version support in app/build.gradle

```
compileSdkVersion 32

minSdkVersion 24
targetSdkVersion 29
```

</details>

<details>
<summary>IOS</summary>

Add the following permission string to info.plist

```
  <key>NSCameraUsageDescription</key>
  <string>The camera is used to scan QR code to pair your device with your atSign</string>
```

Also, update the Podfile with the following lines of code:

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

</details>

<details>
<summary>macOS</summary>

Go to your project folder, macOS/Runner/DebugProfile.entitlements

For release you need to open macOS/Runner/Release.entitlements

and add the following keys:

```
<key>com.apple.security.files.downloads.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

</details>

### 3. Migration guide

<details>
  <summary>From 4.x.x to 5.x.x</summary>

1. Replace `Onboarding(...)` with `AtOnboarding.onboard(...)`
2. Move all config params (`domain`, `atClientPreference`, `rootEnviroment`, ...)
   into `AtOnboardingConfig(...)`
3. The `nextScreen` and `fistTimeAuthNextScreen` has been removed and should be
   using `AtOnboardingResult` to determine which screen will be opened

</details>

## Usage

| Parameters         | Description                                                                                                                      |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| domain             | Domain can differ based on the environment you are using.Default the plugin connects to 'root.atsign.org' to perform onboarding. |
| atClientPreference | The atClientPreference to continue with the onboarding.                                                                          |
| rootEnvironment    | Permission to access the device's location is allowed even when the App is running in the background.                            |
| appAPIKey          | API authentication key for getting free atsigns.                                                                                 |
| isSwitchingAtsign  | Param specifies whether this action is switching atsign or not. Default is false                                                 |
| atsign             | The atsign name when change the primary atsign. Default is null                                                                  |

```dart
TextButton
(
onPressed: () async {
final result = await AtOnboarding.onboard(
context: context,
config: AtOnboardingConfig(
atClientPreference: atClientPreference,
domain: AtEnv.rootDomain,
rootEnvironment: AtEnv.rootEnvironment,
appAPIKey: AtEnv.appApiKey,
),
);
switch (result.status) {
case AtOnboardingResultStatus.success:
final atsign = result.atsign;
// TODO: handle onboard successfully
break;
case AtOnboardingResultStatus.error:
// TODO: handle onboard failure
break;
case AtOnboardingResultStatus.cancel:
// TODO: handle user canceled onboard
break;
}
},
child: Text('Onboard my atSign'),
);
```

- If your app supports windows platform then add `biometric_storage` in app's dependencies

```
dependencies:
 biometric_storage: ^4.1.3
```

### Steps to generate API key :

1. Open URL https://my.atsign.com/login
2. Login with valid credentials
3. Click on My atSign on the dashboard
4. Click on atSign for which you want to generate an API key
5. Click on the manage button
6. Click on Advance settings
7. Click on "Generate New API key"

## Language localization

The strings displayed in `at_onboarding_flutter` are already localized in 2 languages. New languages
will be
supported in the future with minor updates.

Languages supported:

- English ('en')
- French ('fr')

The `at_onboarding_flutter` package can be supplied with additional languages in your code by
setting
the `locale` property in `MaterialApp` class to provide custom values.

## Open source usage and contributions

This is open source code, so feel free to use it as is, suggest changes
or enhancements or create your own version. See
[Contribution Guideline](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md)
for detailed guidance on how to setup tools, tests and make a pull request.
