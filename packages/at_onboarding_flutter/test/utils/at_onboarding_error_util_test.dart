import 'package:at_onboarding_flutter/utils/at_onboarding_error_util.dart';
import 'package:flutter_test/flutter_test.dart';

main() {
  test("pairedAtsign Func", () async {
    final text = AtOnboardingErrorToString().pairedAtsign("@atSignTest");
    expect(
      text,
      "@atSignTest was already paired with this device. First delete/reset this atSign from device to add.",
    );
  });

  test("atsignMismatch Func - isQr: true", () async {
    final text = AtOnboardingErrorToString().atsignMismatch(
      "@atSignTest",
      isQr: true,
    );
    expect(
      text,
      "atSign mismatches. Please provide the QRcode of @atSignTest to pair.",
    );
  });

  test("atsignMismatch Func - isQr: false", () async {
    final text = AtOnboardingErrorToString().atsignMismatch(
      "@atSignTest",
      isQr: false,
    );
    expect(
      text,
      "atSign mismatches. Please provide the backup key file of @atSignTest to pair.",
    );
  });
}
