import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/horizontal_circular_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget horizontalCircularList}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return horizontalCircularList;
    }));
  }

  /// Enable desktop mode before testing this widget.
  /// Functional test cases for Horizontal Circular List
  group('Horizontal Circular List widget Test', () {
    const horizontalCircularList = HorizontalCircularList();
    // Test Case to check  is Horizontal Circular List displayed or not
    testWidgets('Test Case to check Horizontal Circular List is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          horizontalCircularList: horizontalCircularList));
      expect(find.byType(HorizontalCircularList), findsOneWidget);
    });
  });
}
