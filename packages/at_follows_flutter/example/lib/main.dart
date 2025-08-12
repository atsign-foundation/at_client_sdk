import 'dart:async';

import 'package:at_app_flutter/at_app_flutter.dart' show AtEnv;
import 'package:at_follows_flutter_example/screens/follows_screen.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;

import 'services/at_service.dart';

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
        ..isLocalStoreRequired = true
      // TODO set the rest of your AtClientPreference here
      ;
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // * load the AtClientPreference in the background
  Future<AtClientPreference> futurePreference = loadAtClientPreference();
  AtClientPreference? atClientPreference;
  AtAuthService? atClientService;

  final AtSignLogger _logger = AtSignLogger(AtEnv.appNamespace);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // * The onboarding screen (first screen)
      navigatorKey: NavService.navKey,
      home: Scaffold(
          appBar: AppBar(
            title: const Text('at_follows_flutter example app'),
          ),
          body: Builder(
            builder: (context) => Column(
              children: [
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
                      final result = await AtOnboarding.onboard(
                        context: context,
                        config: AtOnboardingConfig(
                          appAPIKey: '477b-876u-bcez-c42z-6a3d',
                          atClientPreference: atClientPreference!,
                          rootEnvironment: AtEnv.rootEnvironment,
                          domain: AtEnv.rootDomain,
                        ),
                      );
                      switch (result.status) {
                        case AtOnboardingResultStatus.success:
                          final atsign = result.atsign;

                          AtService.getInstance().atClientServiceInstance =
                              AtClientMobile.authService(atsign!, atClientPreference!);

                          await AtClientManager.getInstance()
                              .setCurrentAtSign(atsign, atClientPreference!.namespace!, atClientPreference!);
                          await Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NextScreen(),
                            ),
                          );
                          break;
                        case AtOnboardingResultStatus.error:
                          _logger.severe('Onboarding throws ${result.errorCode} error');
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
                              });
                          break;
                        default:
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
                        onPressed: () async {
                          var _atsignsList = await KeychainUtil.getAtsignList();
                          for (String atsign in (_atsignsList ?? [])) {
                            await KeychainUtil.resetAtSignFromKeychain(atsign);
                          }

                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Cleared all paired atsigns')));
                        },
                        child: const Text('Clear paired atsigns', style: TextStyle(color: Colors.black)))),
              ],
            ),
          )),
    );
  }
}

class NavService {
  static GlobalKey<NavigatorState> navKey = GlobalKey();
}
