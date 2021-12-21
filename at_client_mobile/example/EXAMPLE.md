<img width=250px src="https://atsign.dev/assets/img/@platform_logo_grey.svg?sanitize=true">

# at_client_mobile Example

In this example, Let us see how to use `get()`, `put()`, and `delete()` methods in real-time applications.

> **NOTE**: Make sure you have read the documentation to understand the example.

## Get Started

Create a new at_app using [at_app](https://pub.dev/packages/at_app) package.

  ### Generate a new at_app

  ```bash
  at_app create --sample=<package ID> -n=<YOUR NAME SPACE> <APP NAME>
  ```

  > There are 2 more arguments called root-domain (-r) and api-key (-k) which are currently not required. For more details head over to [at_app Flags](https://pub.dev/packages/at_app#executable) documentation.

  **What will be this doing?**
  - This command will generate a simple skeleton of your at_app.
  - Go to the `.env` file and add your namespace if you haven't passed it as an argument.

  ### Run your project

  ```bash
  flutter run
  ```

  ### Start Coding

  By default, there will be at_onboarding_flutter widget implemented in your project. But, we need to make little changes to it.

  #### Login Screen

  - Select the whole Scaffold widget (including body) and hit `Ctrl + .`(Windows/Linux) or `⌘ + .`(Mac) and select **Extract Widget**.
  - Name that widget `LoginScreen` and hit Enter.
  - Now, you will see a new widget called `LoginScreen` in your project.
  - Now let us add some properties values to onboarding widget.

  > **NOTE :** If you using [VisualStudio Code](https://code.visualstudio.com/), You will be catching an Exception called *AtSign not found*. This is because, `Uncaught Exceptions` is checked by default.
  > Ignore this line in debug console - `I/flutter (20332): SEVERE|2021-12-20 19:21:25.593804|AtClientService|Atsign not found`

  ```dart
  AtClientPreference? atClientPreference;
  String? atSign;
  /// Login Screen
  Widget build(context){
  /// ... other widgets ... ///
    Onboarding(
      context: context,
      atClientPreference: atClientPreference!,
      domain: AtEnv.rootDomain,
      appColor: const Color(0xFFF05E3E),
      onboard: (Map<String?, AtClientService> value, String? atsign) {
        atSign = atsign;
        _logger.finer('Successfully onboarded $atsign');
      },
      onError: (Object? error) {
        _logger.severe('Onboarding throws $error error');
      },
      nextScreen: HomeScreen(),
      appAPIKey: AtEnv.appApiKey,
      rootEnvironment: AtEnv.rootEnvironment,
    );
    /// ... ///
  }
  ```

  - Now let's write some app logic. Create a class with instance called `ClientSdkService`.
  ```dart
  class ClientSdkService {
    static final ClientSdkService _singleton = ClientSdkService._internal();

    ClientSdkService._internal();

    factory ClientSdkService.getInstance() {
      return _singleton;
    }
  }
  ```

  - Get necessary instances and variables in `ClientSdkService` class.

  ```dart
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();
  final AtClientManager atClientInstance = AtClientManager.getInstance();
  AtClientService? atClientServiceInstance;
  Map<String?, AtClientService> atClientServiceMap = <String?, AtClientService>{};
  String? atsign;
  AtClient? _getAtClientForAtsign() => atClientInstance.atClient;
  ```

  - Write a function to get AtClient preferences.

  ```dart
  import 'package:path_provider/path_provider.dart' as path_provider;
  
  Future<AtClientPreference> getAtClientPreference({String? cramSecret}) async {
    Directory appDocumentDirectory =
        await path_provider.getApplicationSupportDirectory();
    return AtClientPreference()
      ..isLocalStoreRequired = true
      ..commitLogPath = appDocumentDirectory.path
      ..cramSecret = cramSecret
      ..namespace = AtEnv.namespace
      ..rootDomain = AtEnv.rootDomain
      ..hiveStoragePath = appDocumentDirectory.path;
  }
  ```

  - Write a `get()` function to get the value of the key.
  
  ```dart
  Future<String?> get(AtKey atKey) async {
    try {
      AtValue? result = await _getAtClientForAtsign()!.get(atKey);
      return result.value;
    } on AtClientException catch (atClientExcep) {
      _logger.severe('❌ AtClientException : ${atClientExcep.errorMessage}');
      return null;
    } catch (e) {
      _logger.severe('❌ Exception : ${e.toString()}');
      return null;
    }
  }
  ```

  - Write a `put()` function to put the value of the key.
  
  ```dart
  Future<bool> put(AtKey atKey, String value) async {
    try {
      return _getAtClientForAtsign()!.put(atKey, value);
    } on AtClientException catch (atClientExcep) {
      _logger.severe('❌ AtClientException : ${atClientExcep.errorMessage}');
      return false;
    } catch (e) {
      _logger.severe('❌ Exception : ${e.toString()}');
      return false;
    }
  }
  ```

  - Write a `delete()` function to delete the value of the key.
  
  ```dart
  Future<bool> delete(AtKey atKey) async {
    try {
      return _getAtClientForAtsign()!.delete(atKey);
    } on AtClientException catch (atClientExcep) {
      _logger.severe('❌ AtClientException : ${atClientExcep.errorMessage}');
      return false;
    } catch (e) {
      _logger.severe('❌ Exception : ${e.toString()}');
      return false;
    }
  }
  ```

  - Fetches the atSign from the keychain.
  
  ```dart
  Future<String?> getAtSign() async => _keyChainManager.getAtSign();
  ```

  - After the ClientSdkService is initialized, it will be used in the `onboard` function.

  ```dart
  Onboarding(
    context: context,
    atClientPreference: atClientPreference!,
    domain: AtEnv.rootDomain,
    appColor: const Color(0xFFF05E3E),
    onboard:
        (Map<String?, AtClientService> value, String? atsign) {
      atSign = atsign;
      clientSDKInstance.atsign = atsign!;
      clientSDKInstance.atClientServiceMap = value;
      clientSDKInstance.atClientServiceInstance = value[atsign];
      _logger.finer('Successfully onboarded $atsign');
    },
    onError: (Object? error) {
      _logger.severe('Onboarding throws $error error');
    },
    nextScreen: const HomeScreen(),
    appAPIKey: AtEnv.appApiKey,
    rootEnvironment: AtEnv.rootEnvironment,
  );
  ```

  - Your onboarding function is ready to go. Now, let's add `HomeScreen` widget.
  
  ```dart
  class HomeScreen extends StatelessWidget {
    static const String id = 'HomeScreen';
    const HomeScreen({Key? key}) : super(key: key);

    @override
    Widget build(BuildContext context) {
      /// Get the AtClientManager instance
      var atClientManager = AtClientManager.getInstance();

      return Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard'),
        ),
        body: Center(
          child: Column(
            children: [
              const Text(
                  'Successfully onboarded and navigated to FirstAppScreen'),

              /// Use the AtClientManager instance to get the current atsign
              Text('Current @sign: ${atClientManager.atClient.getCurrentAtSign()}'),
            ],
          ),
        ),
      );
    }
  }
  ```

  - Let us edit the `HomeScreen` widget.
  
  - Add a card with 2 TextFields and a button to put/update values.
<!--
```
Card   
└─Column
  └───TextField(Key: atKey)
  └───TextField(value: value)
  └───Update Button
``` 
-->

  ```dart
  final ClientSdkService _clientSdkService = ClientSdkService.getInstance();
  String? atSign, _key, _value;
  // ...
  // ...
  // ...
  Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15.0),
    ),
    color: Colors.white,
    elevation: 10,
    child: Column(
      children: [
        ListTile(
          title: const Text(
            'Update ',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 20.0,
            ),
          ),
          subtitle: ListView(
            shrinkWrap: true,
            children: <Widget>[
              TextField(
                decoration:
                    const InputDecoration(hintText: 'Enter Key'),
                onChanged: (String key) {
                  _key = key;
                },
              ),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Enter Value',
                ),
                onChanged: (String value) {
                  _value = value;
                },
              ),
            ],
          ),
        ),
        Container(
          width: 150,
          margin: const EdgeInsets.all(10),
          child: TextButton(
            child: const Text(
              'Update',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
            ),
            onPressed: () async {
              // Check if the key and value are not null
              if (_key != null && _value != null) {
                // Put the key in the AtKey
                AtKey pair = AtKey()
                  ..key = _key
                  ..sharedWith = atSign;
                // Call the put function that we 
                // wrote in `ClientSdkService` using it's instance.
                bool _put =
                    await _clientSdkService.put(pair, _value!);
                // Capture 
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${pair.key} value ${_put ? 'updated' : 'not updated'}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    ),
  ),
  ```

  - Now let us add a card to look up the updated values.
<!-- 
```
Card   
└─Column
  └───DropdownButton
  └───Button
``` 
-->
  ```dart
  final TextEditingController? _lookupTextFieldController =
      TextEditingController();
  String? _lookupKey, _lookupValue;
  // ...
  // ...
  // ...
  Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15.0),
    ),
    color: Colors.white,
    elevation: 10,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          title: const Text(
            'Scan',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 20.0,
            ),
          ),
          subtitle: DropdownButton<String>(
            hint: const Text('Select Key'),
            items: _scanItems.map((String? key) {
              return DropdownMenuItem<String>(
                value: key, //key != null ? key : null,
                child: Text(key!),
              );
            }).toList(),
            onChanged: (String? value) {
              setState(() {
                _lookupKey = value;
                _lookupTextFieldController?.text = value!;
              });
            },
            value: _scanItems.isNotEmpty
                ? _lookupTextFieldController!.text.isEmpty
                    ? _scanItems[0]
                    : _lookupTextFieldController?.text
                : '',
          ),
        ),
        Container(
          width: 150,
          margin: const EdgeInsets.all(15),
          child: TextButton(
            child: const Text(
              'Scan',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
            ),
            onPressed: () async {
              // Get the List of AtKeys
              List<AtKey> response =
                  await _clientSdkService.getAtKeys(
                sharedBy: atSign,
              );
              if (response.isNotEmpty) {
                // If AtKeys are not empty, get the value of the selected key
                List<String?> scanList =
                    response.map((AtKey atKey) => atKey.key).toList();
                setState(() => _scanItems = scanList);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Scanning keys and values done.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  ),
  ```
  
  - Now let us add a card to look up the values of the keys.
<!--
```
Card   
└─Column
  └───TextField(Key: atKey)
  └───Fetch value Button
``` 
-->
  ```dart
  Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15.0),
    ),
    color: Colors.white,
    elevation: 10,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          title: const Text(
            'LookUp',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 20.0,
            ),
          ),
          subtitle: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                decoration:
                    const InputDecoration(hintText: 'Enter Key'),
                controller: _lookupTextFieldController,
              ),
              const SizedBox(height: 20),
              const Text(
                'Lookup Result : ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _lookupValue ?? '',
                style: const TextStyle(
                  color: Colors.teal,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.all(10),
          child: TextButton(
            child: const Text(
              'Lookup',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
            ),
            onPressed: () async {
              if (_lookupKey == null) {
                setState(() => _lookupValue = 'The key is empty.');
              } else {
                AtKey lookup = AtKey();
                lookup.key = _lookupKey;
                lookup.sharedWith = atSign;
                String? response =
                    await _clientSdkService.get(lookup);
                setState(() => _lookupValue = response);
              }
            },
          ),
        ),
      ],
    ),
  ),
  ```

  - Now let us implement logout functionality. Let us write an `IconButton` in `AppBar` to make it simple.

  ```dart
  // ClientSDKService class
  Future<void> logout(BuildContext context) async {
    String? atsign = atClientInstance.atClient.getCurrentAtSign();
    await _keyChainManager.deleteAtSignFromKeychain(atsign!);
    atClientServiceInstance = null;
    atClientServiceMap = <String?, AtClientService>{};
    atsign = null;
    Navigator.pop(context);  
  }
  ```

  ```dart
  // HomeScreen
  AppBar(
    title: const Text('Dashboard'),
    actions: [
      IconButton(
        onPressed: () => _clientSdkService.logout(context),
        icon: const Icon(Icons.logout),
      ),
    ],
  ),
  ```