import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/floating_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget floatingIcon}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: Container(child: floatingIcon));
    }));
  }

  /// Functional test cases for Floating Icon Widget
  group('Floating Icon Widget Tests:', () {
    // Test Case to Check Floating Icon is displayed
    const floatingIcon = FloatingIcon();
    testWidgets("Floating Icon is displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(floatingIcon: floatingIcon));
      expect(find.byType(FloatingIcon), findsOneWidget);
    });
  });
}
