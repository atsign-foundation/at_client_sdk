import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/widgets/error_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget errorScreen}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(
        body: Container(
          child: errorScreen,
        ),
      );
    }));
  }

  /// Functional test cases for Error Screen
  group('Error Screen widget Tests:', () {
    final errorScreen = ErrorScreen(
      msg: 'Error',
      onPressed: () {
        log('OnPress is given an action');
      },
    );
    // Test case to identify Error Screen is used in screen or not
    testWidgets("Error Screen widget is used and shown on screen",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(errorScreen: errorScreen));

      expect(find.byType(ErrorScreen), findsOneWidget);
    });
    // Test case to identify msg text is given
    testWidgets("identify contact initial text", (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(errorScreen: errorScreen));

      expect(find.text('Error'), findsOneWidget);
    });
    // Test case to check onTap functionality
    testWidgets("OnPress is given an action", (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(errorScreen: errorScreen));
      expect(errorScreen.onPressed!.call(), null);
    });
  });
}
