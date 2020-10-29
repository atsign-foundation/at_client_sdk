<img src="https://atsign.dev/assets/img/@developersmall.png?sanitize=true">

### Now for some internet optimism.

# at_client
This SDK provides the essential methods for building an app using the @protocol

## Installation:
To use this library in your app, first add it to your pubspec.yaml
```  
dependencies:
  # at_client: ^1.0.0
```
### Add to your project 
```
pub get 
```
### Import in your application code
```
import 'package:at_client/at_client.dart';
```
## Usage
```
var preference = AtClientPreference();
//creating client for alice
// buzz is the namespace
await AtClientImpl.createClient('@alice', 'buzz', preference);
var atClient = await AtClientImpl.getClient('@alice');
```

