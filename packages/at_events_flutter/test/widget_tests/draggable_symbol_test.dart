import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/draggable_symbol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget draggableSymbol}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return draggableSymbol;
    }));
  }

  /// Functional test cases for Draggable Symbol Widget
  group('Draggable Symbol Widget Tests:', () {
    // Test Case to Check Draggable Symbol is displayed
    const draggableSymbol = DraggableSymbol();
    testWidgets("Draggable Symbol is displayed", (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(draggableSymbol: draggableSymbol));
      expect(find.byType(DraggableSymbol), findsOneWidget);
    });
  });
}
