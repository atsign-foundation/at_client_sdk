import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/error_screen.dart';
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

  /// Enable desktop mode before testing this widget.
  /// Functional test cases for Error Screen
  group('Error Screen widget Test', () {
    const errorScreen = ErrorScreen();
    // Test Case to check  is Error Screen displayed or not
    testWidgets('Test Case to check Error Screen is displayed',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(errorScreen: errorScreen));
      expect(find.byType(ErrorScreen), findsOneWidget);
    });
    // Test case to identify msg text is given
    testWidgets("identify contact initial text", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(errorScreen: errorScreen));

      expect(find.text('Error'), findsOneWidget);
    });
    // Test case to check onTap functionality
    testWidgets("OnPress is given an action", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(errorScreen: errorScreen));
      expect(errorScreen.onPressed!.call(), null);
    });
  });
}
