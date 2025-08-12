import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_otp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../onboarding_data_test.dart';

void main() {
  late OnboardingDataTest onboardingDataTest;

  setUpAll(() {
    //Runs once before all test cases are executed.
    onboardingDataTest = OnboardingDataTest();
  });

  Widget _defaultApp({
    ThemeData? theme,
  }) {
    return MaterialApp(
      theme: theme,
      home: Material(
        child: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: AtOnboardingOTPScreen(
                hideReferences: true,
                atSign: "unablecoyote17",
                config: onboardingDataTest.config,
              ),
            );
          },
        ),
      ),
      localizationsDelegates: const [
        AtOnboardingLocalizations.delegate,
      ],
    );
  }

  testWidgets(
    'show Otp Screen',
    (tester) async {
      await tester.pumpWidget(_defaultApp());
      await tester.pump();

      expect(
        find.text(
          AtOnboardingLocalizations.current.title_setting_up_your_atSign,
        ),
        findsOneWidget,
      );
    },
  );
}
