import 'package:at_client_mobile_example/src/screens/home.dart';
import 'package:at_client_mobile_example/src/services/sdk.service.dart';
import 'package:flutter/material.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_app_flutter/at_app_flutter.dart' show AtEnv;

class LoginScreen extends StatefulWidget {
  /// Login screen id.
  /// This helps to navigate from one screen to another screen.
  static const String id = 'LoginScreen';

  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreen createState() => _LoginScreen();
}

class _LoginScreen extends State<LoginScreen> {
  bool showSpinner = false;
  String? atSign;
  ClientSdkService clientSDKInstance = ClientSdkService.getInstance();
  AtClientPreference? atClientPreference;

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
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HomeScreen()));
                      break;
                    case AtOnboardingResultStatus.error:
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Onboard error!${result.message}'),
                        ),
                      );
                      break;
                    case AtOnboardingResultStatus.cancel:
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cancelled!'),
                        ),
                      );
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
                  final result = await AtOnboarding.onboard(
                    context: context,
                    config: AtOnboardingConfig(
                      atClientPreference: atClientPreference!,
                      domain: AtEnv.rootDomain,
                      rootEnvironment: AtEnv.rootEnvironment,
                      appAPIKey: AtEnv.appApiKey,
                    ),
                    isSwitchingAtsign: true,
                  );
                  switch (result.status) {
                    case AtOnboardingResultStatus.success:
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HomeScreen()));
                      break;
                    case AtOnboardingResultStatus.error:
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Onboard error!${result.message}'),
                        ),
                      );
                      break;
                    case AtOnboardingResultStatus.cancel:
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cancelled!'),
                        ),
                      );
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
                if (_atSignsList.isEmpty) {
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
