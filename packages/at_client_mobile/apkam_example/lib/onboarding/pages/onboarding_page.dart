import 'package:apkam_example/constants.dart';
import 'package:apkam_example/home/pages/home_page.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
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
                  atClientPreference: widget.atClientPreference,
                );
                switch (result.getStatus()) {
                  case AtOnboardingResultStatus.success:
                    final atSign = result.atsign;
                    print(atSign);
                    final _ = await AtClientManager.getInstance().setCurrentAtSign(
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
                  case AtOnboardingResultStatus.cancelled:
                    // TODO: handle user canceled onboard
                    break;
                }
              },
              child: const Text('Onboarding'),
            ),
          ],
        ),
      ),
    );
  }
}
