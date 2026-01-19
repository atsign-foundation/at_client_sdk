import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_chat_flutter_example/second_screen.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:flutter/material.dart';
import 'package:flutter_keychain/flutter_keychain.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

const environment = '';
const rootDomain = AtRootDomain('root.atsign.org', 64);
const namespace = 'at_chat_flutter_example';
Future<void> main() async {
  AtSignLogger.root_level = "FINER";
  runApp(const MyApp());
}

Future<AtClientPreference> loadAtClientPreference() async {
  var dir = await getApplicationSupportDirectory();
  return AtClientPreference()
    ..rootDomain = rootDomain.rootDomain
    ..rootPort = rootDomain.rootPort
    ..namespace = namespace
    ..hiveStoragePath = dir.path
    ..commitLogPath = dir.path;
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

  final AtSignLogger _logger = AtSignLogger(namespace);

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
                        // a. Show AtSignSelectionDialog
                        AuthRequest? authRequest =
                            await AtSignSelectionDialog.show(
                          context,
                        );
                        if (authRequest == null) {
                          print(
                              'Authentication cancelled / authRequest is null');
                          return;
                        }
                        authRequest.rootDomain = rootDomain;
                        // b. Show AtKeysFileDialog to pick atKey file
                        var atKeysIo = await AtKeysFileDialog.show(context);
                        if (atKeysIo == null) {
                          throw Exception(
                            'Authentication cancelled / atKeysIo is null',
                          );
                        }
                        var request = AtAuthRequest(
                          authRequest.atSign,
                          atKeysIo: atKeysIo,
                          rootDomain: rootDomain,
                        );
                        // c. Show PkamDialog to complete authentication
                        var response = await PkamDialog.show(
                          context,
                          request: request,
                          backupKeys: [KeychainAtKeysIo()],
                        );
                        if (response != null) {
                          if (response.isSuccessful) {
                            _logger.shout(
                                '${atClientPreference!.rootDomain}@${atClientPreference!.rootPort}');
                            await AtClientManager.getInstance()
                                .setCurrentAtSign(
                              response.atSign,
                              namespace,
                              atClientPreference!,
                              atChops: response.atChops!,
                              atLookUp: response.atLookUp!,
                            );
                            await Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SecondScreen(),
                                ));
                          } else {
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
                          backgroundColor:
                              WidgetStateProperty.all<Color>(Colors.black12),
                        ),
                        onPressed: () {
                          FlutterKeychain.remove(key: '@atsign');
                        },
                        child: const Text('Clear paired atsigns',
                            style: TextStyle(color: Colors.black)))),
              ],
            ),
          )),
    );
  }
}
