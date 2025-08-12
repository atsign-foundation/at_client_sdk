import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/widgets/add_singular_contact_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget addSingleContactDialog}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Container(child: addSingleContactDialog);
    }));
  }

  /// Functional test cases for Add singular contact dialog
  group('Add singular contact dialog widget Tests:', () {
    // Test case to identify Add singular contact dialog is used in screen or not
    testWidgets(
        "Add singular contact dialog widget is used and shown on screen",
        (WidgetTester tester) async {
      const addSingleContactDialog = AddSingleContact(
        atSignName: '@bluebellrelated86',
      );
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          addSingleContactDialog: addSingleContactDialog));

      expect(find.byType(AddSingleContact), findsOneWidget);
    });
    // Test case to check atSignName string is given
    testWidgets("Button text displayed", (WidgetTester tester) async {
      const addSingleContactDialog = AddSingleContact(
        atSignName: '@bluebellrelated86',
      );
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          addSingleContactDialog: addSingleContactDialog));
      expect(find.text('@bluebellrelated86'), findsOneWidget);
    });
  });
}
