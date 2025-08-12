<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

# at_login_flutter

A flutter plugin project for adding zero trust logins using the atProtocol.

## Getting Started

To use this plugin in your app, first add it to pubspec.yaml

```
dependencies:
  at_login_flutter: ^0.0.1
```

### Android
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
compileSdkVersion 29

minSdkVersion 24
targetSdkVersion 29
```

### iOS
Add the following permission string to info.plist

```
  <key>NSCameraUsageDescription</key>
  <string>The camera is used to scan QR code</string>
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

        ## dart: PermissionGroup.camera
        'PERMISSION_CAMERA=1',

        ## dart: PermissionGroup.microphone
        'PERMISSION_MICROPHONE=0',

        ## dart: PermissionGroup.speech
         'PERMISSION_SPEECH_RECOGNIZER=0',

        ## dart: PermissionGroup.photos
        # 'PERMISSION_PHOTOS=0',

        ## dart: [PermissionGroup.location, PermissionGroup.locationAlways, PermissionGroup.locationWhenInUse]
         'PERMISSION_LOCATION=0',

        ## dart: PermissionGroup.notification
        # 'PERMISSION_NOTIFICATIONS=0',

        ## dart: PermissionGroup.mediaLibrary
        'PERMISSION_MEDIA_LIBRARY=0',

        ## dart: PermissionGroup.sensors
         #'PERMISSION_SENSORS=0'

        ## dart: PermissionGroup.bluetooth
        'PERMISSION_BLUETOOTH=0'
      ]
    end
  end
end
```
### Plugin description
This plugin can be added to an app and then used to scan and process a login request, typically 
from a website displaying a QR code that contains a login request.

This plugin provides two screens:

#### AtLogin screen
Your app needs a paired atSign in order to use AtLogin. The at_onboarding widget can be used to set 
up your app with an atSign that can be used to login with your application. 

1. Capture the AtLogin request:
   
   The user can scan a QR code using the camera to capture the AtLogin request.  

2. Approve or reject the request:
   A dialog is presented that shows the request details and asks the atSign owner to approve or 
   reject it.
   
3. Complete the login process
   If approved, AtLogin will publish a cryptograhic proof that the website can lookup which will 
   verify that the atSign login is valid.

#### AtLoginDashboard screen
The AtLoginDashboard can be used to display the history of AtLogin requests (approved or rejected). 
They history records can also be deleted as desired.

### Sample usage
The plugin will return a Map<String, AtClientService> on successful onboarding and throws an 
error if encounters any. Also, the navigation decision can be covered in the app logic.

```
_doLogin(ctxt) async {
  var preference = await _myAppService.getAtClientPreference();
  AtLogin(
    domain: AppConstants.rootDomain,
    context: ctxt,
    atClientPreference: preference,
    nextScreen: AtLoginDashboardWidget(
      atClientPreference:preference,
      atSign: await _myAppService.getAtSign(),
      nextScreen: HomeWidget(),
    ),
    login: (value, atSign) async {
      _myAppService.atClientServiceInstance = value[atSign];
      _myAppService.atClientInstance = _myAppService.atClientServiceInstance.atClient;
      // _atSign = await _myAppService.getAtSign();
      Future.delayed(Duration(milliseconds: 300), () {
        setState(() {});
      });
    },
    onError: (error) {
      Center(child: Text('Onboarding throws $error'));
    },
  );
}
```
