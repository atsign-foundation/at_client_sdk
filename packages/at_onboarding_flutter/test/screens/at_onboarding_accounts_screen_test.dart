import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_accounts_screen.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../onboarding_data_test.dart';

class MockKeyChainManager extends Mock implements KeyChainManager {}

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
              body: AtOnboardingAccountsScreen(
                atsigns: onboardingDataTest.listAtSign,
                newAtsign: onboardingDataTest.atSignTest,
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

  testWidgets('show Accounts Screen has data', (tester) async {
    var onboardingService = OnboardingService.getInstance();
    var mockKeychainManager = MockKeyChainManager();

    when(() => mockKeychainManager.getAtSignListFromKeychain()).thenAnswer(
      (value) async => Future.value(onboardingDataTest.listAtSign),
    );

    onboardingService.keyChainManager = mockKeychainManager;

    await tester.pumpWidget(_defaultApp());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'You already have some existing atsigns. Please select an atSign or else continue with the new one.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('show Accounts Screen empty atSignList', (tester) async {
    var onboardingService = OnboardingService.getInstance();
    var keychainManager = MockKeyChainManager();

    when(() => keychainManager.getAtSignListFromKeychain()).thenAnswer(
      (value) async => Future.value([]),
    );

    onboardingService.keyChainManager = keychainManager;

    await tester.pumpWidget(_defaultApp());
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text(
        'Loading atsigns',
      ),
      findsOneWidget,
    );
  });
}
