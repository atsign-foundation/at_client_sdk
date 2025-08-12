import 'dart:async';

import 'package:at_app_flutter/at_app_flutter.dart' show AtEnv;
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter_example/switch_atsign.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

final StreamController<ThemeMode> updateThemeMode = StreamController<ThemeMode>.broadcast();

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  // * load the AtClientPreference in the background
  Future<AtClientPreference> futurePreference = loadAtClientPreference();
  AtClientPreference? atClientPreference;

  bool isChangeLanguage = false;
  var _currentLocale = const Locale('en', '');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ThemeMode>(
      stream: updateThemeMode.stream,
      initialData: ThemeMode.light,
      builder: (BuildContext context, AsyncSnapshot<ThemeMode> snapshot) {
        ThemeMode themeMode = snapshot.data ?? ThemeMode.light;
        return MaterialApp(
          theme: ThemeData().copyWith(
            brightness: Brightness.light,
            primaryColor: const Color(0xFFf4533d),
            scaffoldBackgroundColor: Colors.white,
            colorScheme:
                ThemeData.light().colorScheme.copyWith(primary: const Color(0xFFf4533d), surface: Colors.white),
          ),
          darkTheme: ThemeData().copyWith(
            brightness: Brightness.dark,
            primaryColor: Colors.blue,
            scaffoldBackgroundColor: Colors.grey[850],
            colorScheme: ThemeData.dark().colorScheme.copyWith(primary: Colors.blue, surface: Colors.grey[850]),
          ),
          locale: _currentLocale,
          localizationsDelegates: const [
            AtOnboardingLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('fr'),
            Locale('en'),
          ],
          themeMode: themeMode,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('MyApp'),
              actions: <Widget>[
                IconButton(
                  onPressed: () {
                    updateThemeMode.sink.add(themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
                  },
                  icon: Icon(
                    Theme.of(context).brightness == Brightness.light
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                  ),
                )
              ],
            ),
            body: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        var preference = await futurePreference;
                        setState(() {
                          atClientPreference = preference;
                        });
                        AtOnboardingResult? result;
                        if (context.mounted) {
                          result = await AtOnboarding.onboard(
                            context: context,
                            config: AtOnboardingConfig(
                              atClientPreference: preference,
                              domain: AtEnv.rootDomain,
                              rootEnvironment: AtEnv.rootEnvironment,
                              appAPIKey: AtEnv.appApiKey,
                              theme: AtOnboardingTheme(
                                primaryColor: Colors.blue,
                                textTheme: const TextTheme(
                                  titleMedium: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  // ),
                                ),
                              ),
                              showPopupSharedStorage: true,
                            ),
                          );
                        }

                        switch (result?.status) {
                          case AtOnboardingResultStatus.success:
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                            break;
                          case null:
                          case AtOnboardingResultStatus.error:
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Colors.red,
                                content: Text('An error has occurred'),
                              ),
                            );
                            break;
                          case AtOnboardingResultStatus.cancel:
                            break;
                        }
                      },
                      child: const Text('Onboard an atSign'),
                    ),
                    const SizedBox(height: 10),
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
                              theme: AtOnboardingTheme(
                                primaryColor: Colors.blue,
                                textTheme: const TextTheme(
                                  titleMedium: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Reset'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text("Change language:"),
                        const SizedBox(width: 10),
                        DropdownButton(
                          onChanged: (value) {
                            setState(() {
                              value == 'en' ? _currentLocale = const Locale('en') : _currentLocale = const Locale('fr');
                            });
                          },
                          value: _currentLocale.languageCode,
                          items: const [
                            DropdownMenuItem(value: 'en', child: Text('English')),
                            DropdownMenuItem(value: 'fr', child: Text('French')),
                          ],
                        )
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
  static final KeyChainManager _keyChainManager = KeyChainManager.getInstance();

  @override
  Widget build(BuildContext context) {
    /// Get the AtClientManager instance
    var atClientManager = AtClientManager.getInstance();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.switch_account),
            tooltip: 'Switch atSign',
            onPressed: () async {
              var atSignList = await KeychainUtil.getAtsignList();
              if (context.mounted) {
                await showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) => AtSignBottomSheet(atSignList: atSignList ?? []),
                );
              }
              setState(() {});
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          children: [
            const Text(
              'Successfully onboarded and navigated to FirstAppScreen',
            ),

            /// Use the AtClientManager instance to get the current atsign
            Text(
              'Current atSign: ${atClientManager.atClient.getCurrentAtSign()}',
            ),
            const SizedBox(
              height: 30,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ElevatedButton(
                  onPressed: () async {
                    _keyChainManager.enableUsingSharedStorage();
                  },
                  child: const Text('Enable share'),
                ),
                const SizedBox(width: 24),
                ElevatedButton(
                  onPressed: () async {
                    _keyChainManager.disableUsingSharedStorage();
                  },
                  child: const Text('Disable share'),
                ),
              ],
            ),
            const SizedBox(
              height: 30,
            ),
            ElevatedButton(
              onPressed: () async {
                _keyChainManager.deleteAllData();
              },
              child: const Text('Delete all data'),
            ),
          ],
        ),
      ),
    );
  }
}
