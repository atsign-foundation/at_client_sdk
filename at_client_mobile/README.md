<img src="https://atsign.dev/assets/img/@developersmall.png?sanitize=true">

### Now for a little internet optimism

# at_client_mobile
This SDK provides the essential methods for building an app using the @protocol
with useful device specific features for iOS and Android applications.

## Installation:
To use this library in your app, first add it to your pubspec.yaml
```  
dependencies:
  at_client_mobile: ^1.0.0+7
```
### Add to your project 
```
pub get 
```
### Import in your application code
```
import 'package:at_client_mobile/at_client_mobile.dart';
```
## Usage
```
var atClientServiceInstance = AtClientService();
finavar appDocumentDirectory =
        await path_provider.getApplicationSupportDirectory();
String path = appDocumentDirectory.path;
var atClientPreference = AtClientPreference()
     ..isLocalStoreRequired = true
     ..commitLogPath = path
     ..syncStrategy = SyncStrategy.IMMEDIATE
     ..rootDomain = AtText.ROOT_DOMAIN
     ..hiveStoragePath = path;
var result = await atClientServiceInstance.onboard(
        atClientPreference: atClientPreference,
        atsign: atsign,
        namespace: AtText.APP_NAMESPACE);
var atClientInstance = atClientServiceInstance.atClient;
```
