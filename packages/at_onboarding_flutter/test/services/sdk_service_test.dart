import 'package:at_onboarding_flutter/services/sdk_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../onboarding_data_test.dart';

class MockSDKService extends Mock implements SDKService {}

main() {
  late MockSDKService mockSDKService;
  late OnboardingDataTest onboardingDataTest;
  late SDKService sdkService;

  setUpAll(() {
    //Runs once before all test cases are executed.
    mockSDKService = MockSDKService();
    onboardingDataTest = OnboardingDataTest();
    sdkService = SDKService();
  });

  group("test getAtSign Func", () {
    test("have atSign", () async {
      when(() => mockSDKService.getAtSign()).thenAnswer(
        (value) => Future.value(onboardingDataTest.atSignTest),
      );

      final atSign = await mockSDKService.getAtSign();
      expect(atSign, onboardingDataTest.atSignTest);
    });

    test("return atSign null", () async {
      when(() => mockSDKService.getAtSign()).thenAnswer(
        (value) => Future.value(null),
      );

      final atSign = await mockSDKService.getAtSign();
      expect(atSign, null);
    });
  });

  group("test formatAtSign Func", () {
    test("formatAtSign don't @", () {
      final result = sdkService.formatAtSign(
        "@${onboardingDataTest.atSignTest}",
      );

      expect(result, "@${onboardingDataTest.atSignTest.toLowerCase()}");
    });

    test("formatAtSign with @", () async {
      final result = sdkService.formatAtSign(
        onboardingDataTest.atSignTest,
      );

      expect(result, "@${onboardingDataTest.atSignTest.toLowerCase()}");
    });
  });
}
