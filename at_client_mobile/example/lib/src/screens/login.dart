import 'package:demo/src/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_app_flutter/at_app_flutter.dart' show AtEnv;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:demo/src/services/sdk.service.dart';

class LoginScreen extends StatefulWidget {
  /// Login screen id.
  /// This helps to navigate from one screen to another screen.
  static const String id = 'LoginScreen';

  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreen createState() => _LoginScreen();
}

class _LoginScreen extends State<LoginScreen> {
  final AtSignLogger _logger = AtSignLogger(AtEnv.appNamespace);
  bool showSpinner = false;
  String? atSign;
  ClientSdkService clientSDKInstance = ClientSdkService.getInstance();
  AtClientPreference? atClientPreference;

  // final AtSignLogger _logger = AtSignLogger('Plugin example app');
  Future<void> call() async {
    await clientSDKInstance
        .getAtClientPreference()
        .then((AtClientPreference? value) => atClientPreference = value);
  }

  @override
  void initState() {
    call();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        title: const Text('Home'),
      ),
      body: Builder(
        builder: (BuildContext context) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Center(
              child: TextButton(
                onPressed: () async {
                  // Onboarding(
                  //   context: context,
                  //   atClientPreference: atClientPreference!,
                  //   domain: AtEnv.rootDomain,
                  //   appColor: Theme.of(context).primaryColor,
                  //   onboard:
                  //       (Map<String?, AtClientService> value, String? atsign) {
                  //     atSign = atsign;
                  //     clientSDKInstance.atsign = atsign!;
                  //     clientSDKInstance.atClientServiceMap = value;
                  //     clientSDKInstance.atClientServiceInstance = value[atsign];
                  //     _logger.finer('Successfully onboarded $atsign');
                  //   },
                  //   onError: (Object? error) {
                  //     // _logger.severe('Onboarding throws $error error');
                  //   },
                  //   nextScreen: const HomeScreen(),
                  //   appAPIKey: AtEnv.appApiKey,
                  //   rootEnvironment: AtEnv.rootEnvironment,
                  // );
                  final result = await AtOnboarding.onboard(
                    context: context,
                    config: AtOnboardingConfig(
                      atClientPreference: atClientPreference!,
                      domain: AtEnv.rootDomain,
                      rootEnvironment: AtEnv.rootEnvironment,
                      appAPIKey: AtEnv.appApiKey,
                    ),
                  );
                  switch (result) {
                    case AtOnboardingResult.success:
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HomeScreen()));
                      break;
                    case AtOnboardingResult.error:
                    // TODO: Handle this case.
                      break;
                    case AtOnboardingResult.cancel:
                    // TODO: Handle this case.
                      break;
                  }
                },
                child: const Text('Onboard'),
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            Center(
              child: TextButton(
                onPressed: () async {
                  final result = await AtOnboarding.start(
                    context: context,
                    config: AtOnboardingConfig(
                      atClientPreference: atClientPreference!,
                      domain: AtEnv.rootDomain,
                      rootEnvironment: AtEnv.rootEnvironment,
                      appAPIKey: AtEnv.appApiKey,
                    ),
                  );
                  switch (result) {
                    case AtOnboardingResult.success:
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HomeScreen()));
                      break;
                    case AtOnboardingResult.error:
                      // TODO: Handle this case.
                      break;
                    case AtOnboardingResult.cancel:
                      // TODO: Handle this case.
                      break;
                  }
                },
                child: const Text('Add another'),
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            TextButton(
              onPressed: () async {
                KeyChainManager _keyChainManager =
                    KeyChainManager.getInstance();
                List<String>? _atSignsList =
                    await _keyChainManager.getAtSignListFromKeychain();
                if (_atSignsList == null || _atSignsList.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '@sign list is empty.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                } else {
                  for (String element in _atSignsList) {
                    await _keyChainManager.deleteAtSignFromKeychain(element);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Keychain cleaned',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
              },
              child: const Text(
                'Reset',
                style: TextStyle(color: Colors.blueGrey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
