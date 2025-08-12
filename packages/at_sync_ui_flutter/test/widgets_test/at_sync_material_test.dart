import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_sync_ui_flutter/at_sync_material.dart';

import '../test_material_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget atSyncIndicatorMaterial}) {
    return TestMaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          SizeConfig().init(context);
          return Scaffold(body: Container(child: atSyncIndicatorMaterial));
        },
      ),
    );
  }

  /// Functional test cases for at_sync indicator material
  group('At_Sync indicator material Tests:', () {
    const atSyncIndicatorMaterial = AtSyncIndicator(
      radius: 25,
      value: 0.0,
      color: Color(0xFFf4533d),
      backgroundColor: Colors.white,
    );
    // Test case to check at_sync_indicator material is displayed
    testWidgets('Notify Screen is used', (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorMaterial: atSyncIndicatorMaterial));
      expect(find.byType(AtSyncIndicator), findsOneWidget);
    });
    // Test case to at_sync indicator material value is given
    testWidgets('Test case to check at_sync indicator material value is given',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorMaterial: atSyncIndicatorMaterial));
      expect(atSyncIndicatorMaterial.value, 0.0);
    });
    // Test case to at_sync indicator material radius is given
    testWidgets('Test case to check at_sync indicator material radius is given',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorMaterial: atSyncIndicatorMaterial));
      expect(atSyncIndicatorMaterial.radius, 25);
    });
    // Test case to at_sync indicator material color is given
    testWidgets('Test case to check at_sync indicator material color is given',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorMaterial: atSyncIndicatorMaterial));
      expect(atSyncIndicatorMaterial.color, const Color(0xFFf4533d));
    });
    // Test case to at_sync indicator material background color is given
    testWidgets(
        'Test case to check at_sync indicator material background color is given',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorMaterial: atSyncIndicatorMaterial));
      expect(atSyncIndicatorMaterial.backgroundColor, Colors.white);
    });
  });
}
