import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/pop_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget popButton}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: Container(child: popButton));
    }));
  }

  /// Functional test cases for Pop Button Widget
  group('Pop Button Widget Tests:', () {
    // Test Case to Check Pop Button is displayed
    const popButton = PopButton(label: 'Hi');
    testWidgets("Pop Button is displayed", (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(popButton: popButton));
      expect(find.byType(PopButton), findsOneWidget);
    });
  });
}
