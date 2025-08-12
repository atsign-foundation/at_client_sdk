import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_invitation_flutter/widgets/otp_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget otpDialog}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return otpDialog;
    }));
  }

  /// Functional test cases for OTP Dialog Widget
  group('OTP Dialog Widget Tests:', () {
    const otpDialog = OTPDialog(
      uniqueID: '25',
      passcode: '25032511',
      webPageLink: 'url for the site',
    );
    // Test Case to Check OTP Dialog is displayed
    testWidgets("OTP Dialog is displayed", (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(otpDialog: otpDialog));
      expect(find.byType(OTPDialog), findsOneWidget);
    });
    // Test case to check uniqueId given
    testWidgets("Test case to check unique id is given",
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(otpDialog: otpDialog));
      expect(otpDialog.uniqueID, '25');
    });
    // Test case to check passcode is given
    testWidgets("Test case to check passcode is given",
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(otpDialog: otpDialog));
      expect(otpDialog.passcode, '25032511');
    });
    // Test case to check web page link is given
    testWidgets("Test case to check web page link is given",
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(otpDialog: otpDialog));
      expect(otpDialog.webPageLink, 'url for the site');
    });
  });
}
