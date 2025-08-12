import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget bottomSheet}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return bottomSheet;
    }));
  }

  /// Functional test cases for group bottom sheet.
  group('Add Single Contacts Group Widget Test', () {
    // Test Case to check group bottom sheet is displayed or not
    testWidgets('Add Contacts Group Widget is Displayed',
        (WidgetTester tester) async {
      const bottomSheet = GroupBottomSheet(
        buttontext: '',
      );
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(bottomSheet: bottomSheet));
      expect(find.byType(GroupBottomSheet), findsOneWidget);
    });
    // Test case to check button text is given
    testWidgets("Button Text is given", (WidgetTester tester) async {
      const bottomSheet = GroupBottomSheet(
        buttontext: 'Click here',
      );
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(bottomSheet: bottomSheet));
      expect(find.text('Click here'), findsOneWidget);
    });

    // Test case to message is given
    testWidgets("Message is given", (WidgetTester tester) async {
      const bottomSheet = GroupBottomSheet(
        buttontext: 'Click here',
        message: 'Hi',
      );
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(bottomSheet: bottomSheet));
      expect(find.text('Hi'), findsOneWidget);
    });

    // Test case to check onPress functionality
    testWidgets("OnPress is given an action", (WidgetTester tester) async {
      final bottomSheet = GroupBottomSheet(
        buttontext: 'Click here',
        onPressed: () {
          log('Onpress given an action');
        },
      );
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(bottomSheet: bottomSheet));
      expect(bottomSheet.onPressed!.call(), null);
    });
  });
}
