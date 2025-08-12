import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_custom_input_field.dart';



import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget desktopCustomInputField}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: desktopCustomInputField);
    }));
  }

  /// Functional test cases for desktop custom Input field
  group('Custom list tile widget Test', () {
    final desktopCustomInputField = DesktopCustomInputField();
    // Test Case to check  is desktop custom Input field displayed or not
    testWidgets(
        'Test Case to check desktop custom Input field is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(desktopCustomInputField: desktopCustomInputField));
      expect(find.byType(DesktopCustomInputField), findsOneWidget);
    });
  });
}
