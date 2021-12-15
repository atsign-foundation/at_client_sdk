import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart'
    show Onboarding;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:at_app_flutter/at_app_flutter.dart' show AtEnv;
import 'package:at_commons/at_commons.dart';

Directory? appSupportDir;

Future<void> main() async {
  await AtEnv.load();
  appSupportDir = await getApplicationSupportDirectory();
  runApp(const MyApp());
}

AtClientPreference loadAtClientPreference() => AtClientPreference()
  ..rootDomain = AtEnv.rootDomain
  ..namespace = AtEnv.appNamespace
  ..hiveStoragePath = appSupportDir!.path
  ..commitLogPath = appSupportDir!.path
  ..isLocalStoreRequired = true;

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // * load the AtClientPreference in the background
  AtClientPreference atClientPreference = loadAtClientPreference();

  final AtSignLogger _logger = AtSignLogger(AtEnv.appNamespace);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // * The onboarding screen (first screen)
      home: Scaffold(
        appBar: AppBar(
          title: const Text('MyApp'),
        ),
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                Onboarding(
                  context: context,
                  atClientPreference: atClientPreference,
                  domain: AtEnv.rootDomain,
                  rootEnvironment: AtEnv.rootEnvironment,
                  appAPIKey: AtEnv.appApiKey,
                  onboard: (value, atsign) {
                    _logger.finer('Successfully onboarded $atsign');
                  },
                  onError: (error) {
                    _logger.severe('Onboarding throws $error error');
                  },
                  nextScreen: const HomeScreen(),
                );
              },
              child: const Text('Onboard an @sign'),
            ),
          ),
        ),
      ),
    );
  }
}

//* The next screen after onboarding (second screen)
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TextEditingController? _putKeyController, _valueController, _getKeyController;
  AtValue? _value;
  bool? valueDeleted;

  /// Get the AtClientManager instance
  var atClientManager = AtClientManager.getInstance();
  Metadata metaData = Metadata()
    ..ttl = 60000
    ..ttb = 30000;
  AtKey atKey = AtKey()..namespace = AtEnv.appNamespace;

  @override
  void initState() {
    super.initState();
    _putKeyController = TextEditingController();
    _valueController = TextEditingController();
    _getKeyController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Welcome ${atClientManager.atClient.getCurrentAtSign()}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 200,
                width: 250,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    TextField(
                      controller: _putKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Key',
                      ),
                      onChanged: (value) {},
                    ),
                    TextField(
                      controller: _valueController,
                      decoration: const InputDecoration(
                        labelText: 'Value',
                      ),
                      onChanged: (value) {},
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await atClientManager.atClient.put(
                          atKey
                            ..key = _putKeyController?.text
                            ..metadata = metaData,
                          _valueController?.text,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Key updated.'),
                          ),
                        );
                      },
                      child: const Text('Put'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Container(
                height: 200,
                width: 250,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    TextField(
                      controller: _getKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Key',
                      ),
                      onChanged: (value) {},
                    ),
                    Text(
                      valueDeleted != null
                          ? 'Deleted: ${valueDeleted! ? 'Yes' : 'No'}'
                          : 'Value: ${_value?.value}',
                      textAlign: TextAlign.start,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              valueDeleted =
                                  await atClientManager.atClient.delete(
                                atKey
                                  ..key = _putKeyController?.text
                                  ..metadata = metaData,
                              );
                              setState(() {});
                            } on KeyNotFoundException catch (_) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Key not found, Try creating a new key.'),
                                ),
                              );
                            }
                          },
                          child: const Text('Delete value'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            setState(() {
                              valueDeleted = null;
                            });
                            try {
                              AtValue atValue =
                                  await atClientManager.atClient.get(
                                atKey
                                  ..key = _putKeyController?.text
                                  ..metadata = metaData,
                              );
                              setState(() {
                                _value = atValue;
                              });
                            } on KeyNotFoundException catch (_) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Key not found, Try creating a new key.'),
                                ),
                              );
                            }
                          },
                          child: const Text('Get value'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
