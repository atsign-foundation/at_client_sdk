import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_theme_flutter/src/widgets/color_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget colorCard}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return colorCard;
    }));
  }

  /// Functional test cases for Color Card Widget
  group('Color Card Widget Tests:', () {
    // Test Case to Check Color Card is displayed
    const colorCard = ColorCard(color: Colors.orange, isSelected: true);
    testWidgets("Color Card is displayed", (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(colorCard: colorCard));
      expect(find.byType(ColorCard), findsOneWidget);
    });
  });
}
