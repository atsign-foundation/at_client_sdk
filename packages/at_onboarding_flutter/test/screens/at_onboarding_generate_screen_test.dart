import 'package:at_onboarding_flutter/screen/at_onboarding_generate_screen.dart';
import 'package:at_onboarding_flutter/services/free_atsign_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:mocktail/mocktail.dart';

import '../onboarding_data_test.dart';

class MockFreeAtsignService extends Mock implements FreeAtsignService {
  @override
  Future getFreeAtsigns() {
    final Response response =
        Response('{"data": {"atsign":"@atSignTest"}}', 200);

    return Future(() => response);
  }
}

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
              body: AtOnboardingGenerateScreen(
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
    );
  }

/*  testWidgets('show Generate Screen', (tester) async {
    await tester.pumpWidget(_defaultApp());
    await tester.pumpAndSettle();

    expect(find.text("Setting up your account"), findsOneWidget);
  });*/
}
