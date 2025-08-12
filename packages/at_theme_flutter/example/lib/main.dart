import 'dart:async';

import 'package:at_app_flutter/at_app_flutter.dart' show AtEnv;
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart'
    show AtOnboarding, AtOnboardingConfig, AtOnboardingResultStatus;
import 'package:at_theme_flutter/at_theme_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;

import 'src/pages/profile_page.dart';

final StreamController<AppTheme> appThemeController =
    StreamController<AppTheme>.broadcast();

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
  AtAuthService? atClientService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppTheme>(
        stream: appThemeController.stream,
        initialData: AppTheme.from(),
        builder: (context, snapshot) {
          AppTheme appTheme = snapshot.data ?? AppTheme.from();
          return InheritedAppTheme(
              theme: appTheme,
              child: MaterialApp(
                // * The onboarding screen (first screen)
                home: Scaffold(
                    appBar: AppBar(
                      title: const Text('at_theme_flutter example app'),
                    ),
                    body: Builder(
                      builder: (context) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
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
                                      rootEnvironment: AtEnv.rootEnvironment,
                                      appAPIKey: AtEnv.appApiKey,
                                    ),
                                  );
                                  switch (result.status) {
                                    case AtOnboardingResultStatus.success:
                                      await Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  const ProfilePage()));
                                      break;
                                    case AtOnboardingResultStatus.error:
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          backgroundColor: Colors.red,
                                          content:
                                              Text('An error has occurred'),
                                        ),
                                      );
                                      break;
                                    case AtOnboardingResultStatus.cancel:
                                      break;
                                  }
                                }
                              },
                              child: const Text('Onboard an atSign'),
                            ),
                          ),
                          const SizedBox(
                            height: 25,
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              var preference = await futurePreference;
                              atClientPreference = preference;
                              if (context.mounted) {
                                AtOnboarding.reset(
                                  context: context,
                                  config: AtOnboardingConfig(
                                    atClientPreference: atClientPreference!,
                                    domain: AtEnv.rootDomain,
                                    rootEnvironment: AtEnv.rootEnvironment,
                                    appAPIKey: AtEnv.appApiKey,
                                  ),
                                );
                              }
                            },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    )),
              ));
        });
  }
}
