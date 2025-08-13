import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_activate_screen.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../onboarding_data_test.dart';

class MockKeyChainManager extends Mock implements KeyChainManager {}

class MockAtStatusImpl extends Mock implements AtStatusImpl {}

void main() {
  late OnboardingDataTest onboardingDataTest;

  setUpAll(() {
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
              body: AtOnboardingActivateScreen(
                hideReferences: true,
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
    'This atSign has already been activated',
    (tester) async {
      var onboardingService = OnboardingService.getInstance();
      var mockKeychainManager = MockKeyChainManager();
      var mockAtStatusImpl = MockAtStatusImpl();

      var atsign = onboardingDataTest.atSignTest.trim().toLowerCase();

      when(() => mockKeychainManager.getAtSign()).thenAnswer(
        (value) async => Future.value(onboardingDataTest.atSignTest),
      );

      when(() => mockKeychainManager.getAtSignListFromKeychain()).thenAnswer(
        (value) async => Future.value([]),
      );

      when(() => mockAtStatusImpl.get("@$atsign")).thenAnswer(
        (value) => Future.value(
          AtStatus(
            rootStatus: RootStatus.found,
            serverStatus: ServerStatus.activated,
            atSignStatus: AtSignStatus.activated,
          ),
        ),
      );

      onboardingService.keyChainManager = mockKeychainManager;
      onboardingService.atStatusImpl = mockAtStatusImpl;

      await tester.pumpWidget(_defaultApp());
      await tester.pump();

      expect(
          find.text(
              "This atSign has already been activated. Please upload your atkeys to pair it with this device"),
          findsOneWidget);
    },
  );

  testWidgets(
    'This atSign has already been activated and paired with this device',
    (tester) async {
      var onboardingService = OnboardingService.getInstance();
      var mockKeychainManager = MockKeyChainManager();
      var mockAtStatusImpl = MockAtStatusImpl();
      var atsign = onboardingDataTest.atSignTest.trim().toLowerCase();

      when(() => mockKeychainManager.getAtSign()).thenAnswer(
        (value) async => Future.value(onboardingDataTest.atSignTest),
      );

      when(() => mockKeychainManager.getAtSignListFromKeychain()).thenAnswer(
        (value) async => Future.value([atsign]),
      );

      when(() => mockAtStatusImpl.get("@$atsign")).thenAnswer(
        (value) => Future.value(
          AtStatus(
            rootStatus: RootStatus.found,
            serverStatus: ServerStatus.activated,
            atSignStatus: AtSignStatus.activated,
          ),
        ),
      );

      onboardingService.keyChainManager = mockKeychainManager;
      onboardingService.atStatusImpl = mockAtStatusImpl;

      await tester.pumpWidget(_defaultApp());
      await tester.pump();

      expect(
          find.text(
              "This atSign has already been activated. Please upload your atkeys to pair it with this device"),
          findsOneWidget);
    },
  );
}
