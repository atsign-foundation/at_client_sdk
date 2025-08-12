import 'package:at_onboarding_flutter/services/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../onboarding_data_test.dart';

class MockOnboardingService extends Mock implements OnboardingService {}

void main() {
  late MockOnboardingService mockOnboardingService;
  late OnboardingDataTest onboardingDataTest;
  late OnboardingService onboardingService;

  setUpAll(() {
    //Runs once before all test cases are executed.
    mockOnboardingService = MockOnboardingService();
    onboardingDataTest = OnboardingDataTest();
    onboardingService = OnboardingService.getInstance();
  });

  group("test getAtSign Func", () {
    test("have atSign", () async {
      when(() => mockOnboardingService.getAtSign()).thenAnswer(
        (value) => Future.value(onboardingDataTest.atSignTest),
      );

      final atSign = await mockOnboardingService.getAtSign();

      verify(() => mockOnboardingService.getAtSign()).called(1);

      expect(atSign, onboardingDataTest.atSignTest);
    });

    test("return atSign null", () async {
      when(() => mockOnboardingService.getAtSign()).thenAnswer(
        (value) => Future.value(null),
      );

      final atSign = await mockOnboardingService.getAtSign();
      expect(atSign, null);
    });
  });

  group("test isUsingSharedStorage Func", () {
    test("UsingSharedStorage", () async {
      when(() => mockOnboardingService.isUsingSharedStorage()).thenAnswer(
        (value) => Future.value(true),
      );

      final result = await mockOnboardingService.isUsingSharedStorage();
      expect(result, true);
    });

    test("don't usingSharedStorage", () async {
      when(() => mockOnboardingService.isUsingSharedStorage()).thenAnswer(
        (value) => Future.value(false),
      );

      final result = await mockOnboardingService.isUsingSharedStorage();
      expect(result, false);
    });
  });

  group("test formatAtSign Func", () {
    test("formatAtSign don't @", () {
      final result = onboardingService.formatAtSign(
        "@${onboardingDataTest.atSignTest}",
      );

      expect(result, "@${onboardingDataTest.atSignTest.toLowerCase()}");
    });

    test("formatAtSign with @", () {
      final result = onboardingService.formatAtSign(
        onboardingDataTest.atSignTest,
      );

      expect(result, "@${onboardingDataTest.atSignTest.toLowerCase()}");
    });
  });

  group("test getAtsignList Func", () {
    test("AtsignList has data", () async {
      when(() => mockOnboardingService.getAtsignList()).thenAnswer(
        (value) => Future.value(onboardingDataTest.listAtSign),
      );

      final result = await mockOnboardingService.getAtsignList();

      expect(result, onboardingDataTest.listAtSign);
    });

    test("AtsignList empty", () async {
      when(() => mockOnboardingService.getAtsignList()).thenAnswer(
        (value) => Future.value([]),
      );

      final result = await mockOnboardingService.getAtsignList();

      expect(result, []);
    });
  });
}
