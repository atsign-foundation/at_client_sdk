import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_sync_ui_flutter/at_sync_cupertino.dart';

import '../test_material_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp(
      {required Widget atSyncIndicatorCupertino}) {
    return TestMaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          SizeConfig().init(context);
          return Scaffold(body: Container(child: atSyncIndicatorCupertino));
        },
      ),
    );
  }

  /// Functional test cases for at_sync indicator cupertino
  group('At_Sync indicator cupertino Tests:', () {
    const atSyncIndicatorCupertino = AtSyncIndicator(
      value: 0.0,
      color: Color(0xFFf4533d),
    );
    // Test case to check at_sync_indicator cupertino is displayed
    testWidgets('Notify Screen is used', (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorCupertino: atSyncIndicatorCupertino));
      expect(find.byType(AtSyncIndicator), findsOneWidget);
    });
    // Test case to at_sync indicator cupertino value is given
    testWidgets('Test case to check at_sync indicator cupertino value is given',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorCupertino: atSyncIndicatorCupertino));
      expect(atSyncIndicatorCupertino.value, 0.0);
    });
    // Test case to at_sync indicator cupertino color is given
    testWidgets('Test case to check at_sync indicator cupertino color is given',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          atSyncIndicatorCupertino: atSyncIndicatorCupertino));
      expect(atSyncIndicatorCupertino.color, const Color(0xFFf4533d));
    });
  });
}
