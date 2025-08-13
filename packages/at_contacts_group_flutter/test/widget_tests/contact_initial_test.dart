import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/contact_initial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget contactInitial}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return contactInitial;
    }));
  }

  /// Functional test cases for contact initial
  group('Contact Initial Widget Test', () {
    final contactInitial = ContactInitial(initials: '@');
    // Test Case to check confirmation dialog is displayed or not
    testWidgets('Test Case to check contact initial is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(contactInitial: contactInitial));
      expect(find.byType(ContactInitial), findsOneWidget);
    });

    // Test case to check initial is given
    testWidgets("Initial is given", (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(contactInitial: contactInitial));
      expect(find.text('@'), findsOneWidget);
    });

  });
}
