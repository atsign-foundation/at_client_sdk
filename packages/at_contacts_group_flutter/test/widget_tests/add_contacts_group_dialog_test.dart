import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/add_contacts_group_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget addContactsGroupDialog}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return addContactsGroupDialog;
    }));
  }

  /// Functional test cases for add contacts group dialog
  group('Add Contacts Group Dialog Widget Test', () {
    // Test Case to Add contact dialog is displayed or not
    testWidgets('Add Contacts Group Widget is Displayed',
        (WidgetTester tester) async {
      const addContactDialog = AddContactDialog();
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(addContactsGroupDialog: addContactDialog));
      expect(find.byType(AddContactDialog), findsOneWidget);
    });
  });
}
