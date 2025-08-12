import 'dart:io';

import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_pair_screen.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_reference_screen.dart';
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
              body: AtOnboardingPairScreen(
                hideReferences: true,
                atSign: "unablecoyote17",
                onGenerateSuccess: ({
                  required String atSign,
                  required String secret,
                }) {},
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
    'show Pair Screen',
    (tester) async {
      await tester.pumpWidget(_defaultApp());
      await tester.pumpAndSettle();

      expect(
        find.text(
          AtOnboardingLocalizations.current.title_setting_up_your_atSign,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('show Reference Webview', (tester) async {
    await tester.pumpWidget(_defaultApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    if (Platform.isAndroid || Platform.isIOS) {
      expect(find.byType(AtOnboardingReferenceScreen), findsOneWidget);
    } else {
      expect(true, true);
    }
  });

  testWidgets('send code', (tester) async {
    await tester.pumpWidget(_defaultApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send Code'));
    await tester.pumpAndSettle();
  });
}
