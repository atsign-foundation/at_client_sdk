import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget errorScreen}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return errorScreen;
    }));
  }

  /// Functional test cases for Error Screen Widget
  group('Error Screen Widget Tests:', () {
    final errorScreen = ErrorScreen(
      onPressed: () {
        log('OnPress is given an action');
      },
    );
    // Test Case to Check Error Screen is displayed
    testWidgets("Error Screen is displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(errorScreen: errorScreen));
      expect(find.byType(ErrorScreen), findsOneWidget);
    });

    // Test case to check onTap functionality
    testWidgets("OnPress is given an action", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(errorScreen: errorScreen));
      expect(errorScreen.onPressed!.call(), null);
    });
  });
}
