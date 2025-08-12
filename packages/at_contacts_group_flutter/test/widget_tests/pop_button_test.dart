import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/pop_button.dart';
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

  /// Functional test cases for Pop Button
  group('Pop Button widget Test', () {
    const popButton = PopButton(
      label: 'Click here',
    );
    // Test Case to check  is Pop Button displayed or not
    testWidgets('Test Case to check Pop Button is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(popButton: popButton));
      expect(find.byType(PopButton), findsOneWidget);
    });
  });
}
