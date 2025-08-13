import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/custom_input_field.dart'
    as custominputfield;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget customInputField}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: customInputField);
    }));
  }

  /// Functional test cases for custom input field
  group('Custom input field widget Test', () {
    const customInputField = custominputfield.CustomInputField();
    // Test Case to check  is contact selection bottom sheet displayed or not
    testWidgets('Test Case to check custom input field is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(customInputField: customInputField));
      expect(find.byType(custominputfield.CustomInputField), findsOneWidget);
    });
  });
}
