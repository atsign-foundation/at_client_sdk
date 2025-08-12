import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/widgets/custom_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget contactsSearchField}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(
        body: Container(
          child: contactsSearchField,
        ),
      );
    }));
  }

  /// Functional test cases for Contacts search field
  group('Contacts search field widget Tests:', () {
    // Test case to identify Contacts search field is used in screen or not
    testWidgets("Contacts search field widget is used and shown on screen",
        (WidgetTester tester) async {
      final contactsSearchField = ContactSearchField('Contacts', (v) {
        log(v);
      });
      await tester.pumpWidget(
          wrapWidgetWithMaterialApp(contactsSearchField: contactsSearchField));

      expect(find.byType(ContactSearchField), findsOneWidget);
    });
  });
}
