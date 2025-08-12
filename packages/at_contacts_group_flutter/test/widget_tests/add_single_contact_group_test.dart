import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/add_single_contact_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget addSingleContactGroup}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return addSingleContactGroup;
    }));
  }

  /// Functional test cases for add single contact group.
  group('Add Single Contacts Group Widget Test', () {
    // Test Case to Add single contact contact is displayed or not
    testWidgets('Add Contacts Group Widget is Displayed',
        (WidgetTester tester) async {
      const addSingleContactGroup = AddSingleContact();
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          addSingleContactGroup: addSingleContactGroup));
      expect(find.byType(AddSingleContact), findsOneWidget);
    });
    // Test case to check atsign name is given or not
    testWidgets("Atsign name is displayed", (WidgetTester tester) async {
      const addSingleContactGroup = AddSingleContact(
        atSignName: '@',
      );
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          addSingleContactGroup: addSingleContactGroup));
      expect(find.text('@'), findsOneWidget);
    });
  });
}
