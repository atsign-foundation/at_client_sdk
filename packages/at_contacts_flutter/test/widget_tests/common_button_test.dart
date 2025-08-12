import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/widgets/common_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget commonButton}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(
        body: Container(
          child: commonButton,
        ),
      );
    }));
  }

  /// Functional test cases for Common Button
  group('Common Button widget Tests:', () {
    final commonButton = CommonButton('Click', () {
      log('On Tap is given an action');
    });
    // Test case to identify Common Button is used in screen or not
    testWidgets("Common Button widget is used and shown on screen",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(commonButton: commonButton));

      expect(find.byType(CommonButton), findsOneWidget);
    });
    // Test case to check button string is given
    testWidgets("Button text displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(commonButton: commonButton));
      expect(find.text('Click'), findsOneWidget);
    });

    // Test case to check onTap functionality
    testWidgets("OnPress is given an action", (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(commonButton: commonButton));
      expect(commonButton.onTap.call(), null);
    });
  });
}
