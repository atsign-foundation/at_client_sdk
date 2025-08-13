import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_theme_flutter/src/widgets/theme_mode_card.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget themeModeCard}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return themeModeCard;
    }));
  }

  /// Functional test cases for Theme Mode Card Widget
  group('Theme Mode Card Widget Tests:', () {
    // Test Case to Check Theme Mode Card is displayed
    const themeModeCard = ThemeModeCard(
        primaryColor: Colors.purple,
        brightness: Brightness.light,
        isSelected: true);
    testWidgets("Theme Mode Card is displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(themeModeCard: themeModeCard));
      expect(find.byType(ThemeModeCard), findsOneWidget);
    });
  });
}
