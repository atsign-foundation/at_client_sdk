import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/custom_heading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget customHeading}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return customHeading;
    }));
  }

  /// Functional test cases for Custom Heading Widget
  group('Custom Heading Widget Tests:', () {
    // Test Case to Check Custom Heading is displayed
    const customHeading = CustomHeading();
    testWidgets("Custom Heading is displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(customHeading: customHeading));
      expect(find.byType(CustomHeading), findsOneWidget);
    });
  });
}
