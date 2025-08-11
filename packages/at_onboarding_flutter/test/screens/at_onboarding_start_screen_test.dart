import 'package:at_auth/at_auth.dart';
import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_start_screen.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../onboarding_data_test.dart';

class MockOnboardingService extends Mock implements OnboardingService {
  @override
  Future<void> initialSetup({required bool usingSharedStorage}) async {
    return;
  }

  @override
  Future<bool> onboard({String? cramSecret, AtOnboardingRequest? atOnboardingRequest}) {
    throw OnboardingStatus.ACTIVATE;
  }
}

void main() {
  late OnboardingDataTest onboardingDataTest;
  late MockOnboardingService mockOnboardingService;

  setUpAll(() {
    //Runs once before all test cases are executed.
    onboardingDataTest = OnboardingDataTest();
    mockOnboardingService = MockOnboardingService();
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
              body: AtOnboardingStartScreen(
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

  testWidgets('show Start Screen', (tester) async {
    when(() => mockOnboardingService.initialSetup(usingSharedStorage: true));

    await tester.pumpWidget(_defaultApp());

    await tester.pump();

    expect(find.text("Onboarding"), findsOneWidget);
  });
}
