import 'package:apkam_example/constants.dart';
import 'package:apkam_example/home/pages/home_page.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({required this.atClientPreference, super.key});

  final AtClientPreference atClientPreference;

  @override
  OnboardingPageState createState() => OnboardingPageState();
}

class OnboardingPageState extends State<OnboardingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                final result = await AtOnboarding.onboard(
                  context: context,
                  config: AtOnboardingConfig(
                    atClientPreference: widget.atClientPreference,
                    rootEnvironment: RootEnvironment.Production,
                    hideQrScan: true,
                  ),
                );
                switch (result.status) {
                  case AtOnboardingResultStatus.success:
                    final atSign = result.atsign;
                    print(atSign);
                    final _ =
                        await AtClientManager.getInstance().setCurrentAtSign(
                      atSign!,
                      appNamespace,
                      widget.atClientPreference,
                    );
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const HomePage(),
                        ),
                      );
                    }
                    break;
                  case AtOnboardingResultStatus.error:
                    // TODO: handle onboard failure
                    break;
                  case AtOnboardingResultStatus.cancel:
                    // TODO: handle user canceled onboard
                    break;
                }
              },
              child: const Text('Onboarding'),
            ),
            ElevatedButton(
              onPressed: () async {
                final result = await AtOnboarding.onboard(
                  context: context,
                  config: AtOnboardingConfig(
                    atClientPreference: widget.atClientPreference,
                    rootEnvironment: RootEnvironment.Production,
                    hideQrScan: true,
                  ),
                  isSwitchingAtsign: true,
                  atsign: '39acidhouse',
                );
                switch (result.status) {
                  case AtOnboardingResultStatus.success:
                    final atSign = result.atsign;
                    print(atSign);
                    final _ =
                        await AtClientManager.getInstance().setCurrentAtSign(
                      atSign!,
                      appNamespace,
                      widget.atClientPreference,
                    );
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const HomePage(),
                        ),
                      );
                    }
                    break;
                  case AtOnboardingResultStatus.error:
                    // TODO: handle onboard failure
                    break;
                  case AtOnboardingResultStatus.cancel:
                    // TODO: handle user canceled onboard
                    break;
                }
              },
              child: const Text('Switch'),
            ),
          ],
        ),
      ),
    );
  }
}
