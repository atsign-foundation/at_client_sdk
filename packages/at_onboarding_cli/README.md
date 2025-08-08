<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_onboarding_cli)](https://pub.dev/packages/at_onboarding_cli) [![pub points](https://img.shields.io/pub/points/at_onboarding_cli?logo=dart)](https://pub.dev/packages/at_onboarding_cli/score) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

# at_onboarding_cli

## Introduction
at_onboarding_cli is a library to authenticate and onboard atSigns.

## Get Started

To add this package as the dependency in your pubspec.yaml

```yaml 
dependencies:
  at_onboarding_cli: ^1.3.0
```
Getting Dependencies

```sh
dart pub get 
```

To import the library in your application code

```dart
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
```

## Usage
Use cases for at_onboarding_cli:\
    1) Authentication\
    2) Onboarding (Activation)\
    3) activate_cli\
    4) register_cli
    5) APKAM enrollments

- Set `AtOnboardingPreference` to your preferred settings. These preferences will be used to configure the `AtOnboardingService`. 
    
 ```
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
        ..rootDomain = 'root.atsign.org
        ..qrCodePath = 'storage/qr_code.png'
        ..hiveStoragePath = 'storage/hive'
        ..namespace = 'example'
        ..downloadPath = 'storage/files'
        ..isLocalStoreRequired = true
        ..commitLogPath = 'storage/commitLog'
        ..cramSecret = '<your cram secret>'
        ..privateKey = '<your private key here>'
        ..atKeysFilePath = 'storage/alice_key.atKeys';
 ```

### Authentication:
Proving that one actually owns the atSign. User needs to authenticate before performing operations on that atSign. Operations include reading, writing, deleting or updating data in the atsign's keystore and sending notifications from that atSign.

#### Steps to Authenticate
   1) Import at_onboarding_cli.
   2) Set preferences using AtOnboardingPreference. Either of secret key or path to .atKeysFile need to be provided to authenticate.
   3) Instantiate AtOnboardingServiceImpl using the required atSign and a valid instance of AtOnboardingPreference.
   4) Call the authenticate method on AtOnboardingService.
   5) Use getAtLookup/getAtClient to get authenticated instances of AtLookup and AtClient respectively which can be used to perform more complex operations on the atSign.
```
AtOnboardingService atOnboardingService = AtOnboardingServiceImpl('@alice', atOnboardingPreference);
atOnboardingService.authenticate();
AtClient? atClient = await atOnboardingService.atClient;
AtLookup? atLookup = atOnboardingService.atLookUp;
```

### Onboarding: 
Performing initial one-time authentication using cram secret encoded in the qr_code. This process activates the atSign making it ready to use.

#### Steps to onboard:
   1) Import at_cli_onboarding.
   2) Set preferences using AtOnboardingPreference. Provide the cram secret for the atsign if you have one.
   3) If you do not have a cram secret you can just leave it blank. In this case a verification code will be sent to your registered email which you can provide to activate your already registered atsign.
   4) Instantiate AtOnboardingServiceImpl using the required atSign and a valid instance of AtOnboardingPreference.
   5) Call the onboard() in AtOnboardingServiceImpl.
   6) Use authenticated instances of atClient/atLookup now available in AtOnboardingServiceImpl's instance to perform complex operations on the atSign.
 ```
AtOnboardingService atOnboardingService = AtOnboardingServiceImpl('@alice', atOnboardingPreference);
atOnboardingService.onboard();
> Successfully sent verification code to your registered e-mail
> [Action Required] Enter your verification code:
<your 4 charcter code here>
AtClient? atClient = await atOnboardingService.atClient();
AtLookup? atLookup = atOnboardingService.atLookUp();
```
Please refer to [example](https://pub.dev/packages/at_onboarding_cli/example) to better understand the usage.

### activate_cli:
A simple tool to onboard(activate) an atSign through command-line arguments

#### Usage 1:
Run the following commands in your command-line tool (Terminal, CMD, PowerShell, etc)

##### To activate using a verification code
```
dart pub global activate at_onboarding_cli
at_activate -a your_atsign
> Successfully sent verification code to your registered e-mail
> [Action Required] Enter your verification code:
<your 4 charcter code here>
```

##### To activate using your cram secret
```
dart pub global activate at_onboarding_cli
at_activate -a your_atsign -c your_cram_secret
```

#### Usage 2:
   1) Clone code from https://github.com/atsign-foundation/at_libraries
   2) Change directory to at_libraries/at_onboarding_cli in the cloned repository
   3) Run `dart pub get`
   4) Run the following command
```
dart run bin/activate_cli.dart -a your_atsign -c your_cram_secret

                             (or)

dart run bin/activate_cli.dart -a your_atsign (to activate using verification code)
```
[IMPORTANT] You can find your .atKeysFile in directory ~/.atsign/keys after successful activation


### register_cli:
A command-line tool to get yourself a free atsign. This tool fetches a free atsign and registers it to the email provided as arguments.

#### Usage 1:
Run the following commands in you command-line tool (Terminal, CMD, PowerShell, etc)
```
dart pub global activate at_onboarding_cli
at_register -e your_email
```

#### Usage 2:
   1) Clone code from https://github.com/atsign-foundation/at_libraries
   2) Change directory to at_libraries/at_onboarding_cli in the cloned repository
   3) Run `dart pub get`
   4) Run the following command
```
dart run bin/register.dart -e email@email.com
```
   5) Enter verification code sent to the provided email when prompted
   6) register_cli fetches the cramkey and the automatically calls activate_cli to activate the fetched atsign
   7) You can find your .atKeysFile in directory at_onboarding_cli/keys after successful activation

### APKAM Enrollments
- Please refer to examples/readme.md in the github repository for at_onboarding_cli

## Open source usage and contributions

This is freely licensed open source code, so feel free to use it as is, suggest changes or enhancements or create your
own version. See CONTRIBUTING.md for detailed guidance on how to setup tools, tests and make a pull request.