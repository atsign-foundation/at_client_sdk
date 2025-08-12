import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_qrcode_screen.dart';
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
              body: AtOnboardingQRCodeScreen(
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
    'show QRCode Screen',
    (tester) async {
      await tester.pumpWidget(_defaultApp());
      await tester.pump(const Duration(seconds: 1));

      expect(find.text("Scan your QR!"), findsOneWidget);
    },
    variant: TargetPlatformVariant.mobile(),
  );
}
