import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/screen/at_onboarding_backup_screen.dart';
import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../onboarding_data_test.dart';

class MockOnboardingService extends Mock implements OnboardingService {}

void main() {
  late OnboardingDataTest onboardingDataTest;
  late MockOnboardingService mockOnboardingService;

  setUpAll(() {
    onboardingDataTest = OnboardingDataTest();
    mockOnboardingService = MockOnboardingService();
    mockOnboardingService.setAtsign = onboardingDataTest.atSignTest;
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
              body: AtOnboardingBackupScreen(
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

  testWidgets('show Backup Screen atSign null', (tester) async {
    await tester.pumpWidget(_defaultApp());
    await tester.pump();

    expect(find.text('An atSign is required.'), findsOneWidget);
  });

  testWidgets(
    'show Backup Screen has atSign',
    (tester) async {
      var onboardingService = OnboardingService.getInstance();
      onboardingService.setAtsign = onboardingDataTest.atSignTest;
      await tester.pumpWidget(_defaultApp());
      await tester.pump();

      expect(
        find.text(
          AtOnboardingLocalizations.current.title_save_your_key,
        ),
        findsOneWidget,
      );
    },
  );
}
