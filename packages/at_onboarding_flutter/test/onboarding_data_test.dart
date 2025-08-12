import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class OnboardingDataTest {
  final String atSignTest = "atSignTest";
  final List<String> listAtSign = [
    "atSignTest1",
    "atSignTest2",
    "atSignTest3",
  ];

  final AtOnboardingConfig config = AtOnboardingConfig(
    rootEnvironment: RootEnvironment.Staging,
    atClientPreference: AtClientPreference()
      ..rootDomain = 'root.atsign.org'
      ..namespace = 'at_skeleton_app'
      ..isLocalStoreRequired = true,
    domain: "root.atsign.org",
  );
}

main() {
  test("test", () {
    expect(1, 1);
  });
}
