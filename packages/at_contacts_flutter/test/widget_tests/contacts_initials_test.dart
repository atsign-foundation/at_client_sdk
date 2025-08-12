import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/widgets/contacts_initials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget contactInitial}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(
        body: Container(
          child: contactInitial,
        ),
      );
    }));
  }

  /// Functional test cases for Contacts Initial
  group('Contacts Initial widget Tests:', () {
    // Test case to identify Contacts Initial is used in screen or not
    testWidgets("Contacts Initial widget is used and shown on screen",
        (WidgetTester tester) async {
      final contactInitial = ContactInitial(initials: 'A');
      await tester.pumpWidget(
          wrapWidgetWithMaterialApp(contactInitial: contactInitial));

      expect(find.byType(ContactInitial), findsOneWidget);
    });
    // Test case to identify contact initial text
    testWidgets("identify contact initial text", (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          contactInitial: ContactInitial(initials: '@')));

      expect(find.text('@'), findsOneWidget);
    });
  });
}
