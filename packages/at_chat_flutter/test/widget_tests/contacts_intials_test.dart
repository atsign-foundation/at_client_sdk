import 'package:at_chat_flutter/utils/colors.dart';
import 'package:at_chat_flutter/widgets/contacts_initials.dart';
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget contactInitial}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return contactInitial;
    }));
  }

  /// Functional test cases for [contactInitial]
  group('Contacts Initial widget Tests:', () {
    // Test case to identify contact initial is used in screen or not
    testWidgets("Button widget is used and shown on screen",
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          contactInitial: ContactInitial(initials: '@')));

      expect(find.byType(ContactInitial), findsOneWidget);
    });

    // Test case to identify contact initial text
    testWidgets("identify contact initial text", (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          contactInitial: ContactInitial(initials: '@')));

      expect(find.text('@'), findsOneWidget);
    });

    // Test case to check contact initial to check background color
    testWidgets('Contacts initial with background color',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          contactInitial: ContactInitial(
        initials: '@',
        backgroundColor: CustomColors.defaultColor,
      )));
      final contactsInitial =
          tester.widget<ContactInitial>(find.byType(ContactInitial));
      expect(
        contactsInitial.backgroundColor,
        CustomColors.defaultColor,
      );
    });

    // Test case to check contact initial to check given without background color
    testWidgets('Contacts initial without background color',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          contactInitial: ContactInitial(
        initials: '@',
      )));
      final contactsInitial =
          tester.widget<ContactInitial>(find.byType(ContactInitial));
      expect(contactsInitial.backgroundColor, null);
    });
  });
}
