import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_flutter/widgets/horizontal_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget horizontalCircularList}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(
        body: Container(
          child: horizontalCircularList,
        ),
      );
    }));
  }

  /// Functional test cases for Horizontal circular list
  group('Horizontal circular list widget Tests:', () {
    // Test case to identify Horizontal circular list is used in screen or not
    testWidgets("Horizontal circular list widget is used and shown on screen",
        (WidgetTester tester) async {
      const horizontalCircularList = HorizontalCircularList();
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          horizontalCircularList: horizontalCircularList));

      expect(find.byType(HorizontalCircularList), findsOneWidget);
    });
  });
}
