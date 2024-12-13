import 'package:apkam_example/home/pages/home_page.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter/material.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  OnboardingPageState createState() => OnboardingPageState();
}

class OnboardingPageState extends State<OnboardingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result = await AtOnboarding.onboard(
              context: context,
              config: AtOnboardingConfig(
                atClientPreference: AtClientPreference(),
                rootEnvironment: RootEnvironment.Production,
                hideQrScan: true,
              ),
            );
            switch (result.status) {
              case AtOnboardingResultStatus.success:
                final atsign = result.atsign;
                print(atsign);
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => HomePage(),
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
      ),
    );
  }
}
