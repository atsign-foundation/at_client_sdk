import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_location_flutter/common_components/pop_button.dart';
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

  /// Functional test cases for [popButton]
  group('Pop Button widget Tests:', () {
    const popButton = PopButton(label: 'Pop up');
    // Test case to identify Pop Button is used in screen or not
    testWidgets("Test case to identify Pop Button is used in screen or not",
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(popButton: popButton));

      expect(find.byType(PopButton), findsOneWidget);
    });
  });
}
