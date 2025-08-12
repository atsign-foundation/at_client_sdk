import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
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

  // ignore: unused_element
  Widget _defaultApp({
    ThemeData? theme,
  }) {
    return MaterialApp(
      theme: theme,
      home: Material(
        child: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: AtOnboardingReferenceScreen(
                title: "WebView",
                url: "https://pub.dev/",
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

/*  testWidgets('show Reference Screen', (tester) async {
    await tester.pumpWidget(_defaultApp());
    await tester.pump();

    expect(find.text("WebView"), findsOneWidget);
  });*/
}
