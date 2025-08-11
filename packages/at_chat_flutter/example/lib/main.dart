import 'dart:async';

import 'package:at_app_flutter/at_app_flutter.dart' show AtEnv;
import 'package:at_chat_flutter_example/second_screen.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:flutter/material.dart';
import 'package:flutter_keychain/flutter_keychain.dart';
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;

Future<void> main() async {
  await AtEnv.load();
  runApp(const MyApp());
}

Future<AtClientPreference> loadAtClientPreference() async {
  var dir = await getApplicationSupportDirectory();
  return AtClientPreference()
    ..rootDomain = AtEnv.rootDomain
    ..namespace = AtEnv.appNamespace
    ..hiveStoragePath = dir.path
    ..commitLogPath = dir.path
    ..isLocalStoreRequired = true;
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // * load the AtClientPreference in the background
  Future<AtClientPreference> futurePreference = loadAtClientPreference();
  AtClientPreference? atClientPreference;
  AtAuthService? atAuthService;

  final AtSignLogger _logger = AtSignLogger(AtEnv.appNamespace);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // * The onboarding screen (first screen)
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Plugin example app'),
          ),
          body: Builder(
            builder: (context) => Column(
              children: [
                const SizedBox(
                  height: 25,
                ),
                Container(
                    padding: const EdgeInsets.all(10.0),
                    child: const Center(
                      child: Text(
                          'A client service should create an atClient instance and call onboard method before navigating to QR scanner screen',
                          textAlign: TextAlign.center),
                    )),
                const SizedBox(
                  height: 25,
                ),
                Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      var preference = await futurePreference;
                      setState(() {
                        atClientPreference = preference;
                      });
                      if (context.mounted) {
                        final result = await AtOnboarding.onboard(
                          context: context,
                          config: AtOnboardingConfig(
                            atClientPreference: atClientPreference!,
                            domain: AtEnv.rootDomain,
                            appAPIKey: '477b-876u-bcez-c42z-6a3d',
                            rootEnvironment: AtEnv.rootEnvironment,
                          ),
                        );

                        switch (result.status) {
                          case AtOnboardingResultStatus.success:
                            if (mounted) {
                              await Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SecondScreen(),
                                  ));
                            }
                            break;
                          case AtOnboardingResultStatus.error:
                            _logger.severe('Onboarding throws ${result.errorCode} error');
                            if (mounted) {
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    content: const Text('Something went wrong'),
                                    actions: [
                                      TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          child: const Text('ok'))
                                    ],
                                  );
                                },
                              );
                            }
                            break;
                          case AtOnboardingResultStatus.cancel:
                            break;
                        }
                      }
                    },
                    child: const Text('Start onboarding'),
                  ),
                ),
                const SizedBox(
                  height: 25,
                ),
                Center(
                    child: TextButton(
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all<Color>(Colors.black12),
                        ),
                        onPressed: () {
                          FlutterKeychain.remove(key: '@atsign');
                        },
                        child: const Text('Clear paired atsigns', style: TextStyle(color: Colors.black)))),
              ],
            ),
          )),
    );
  }
}
