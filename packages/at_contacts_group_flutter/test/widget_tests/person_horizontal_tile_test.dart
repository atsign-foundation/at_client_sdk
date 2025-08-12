import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/person_horizontal_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget customPersonHorizontalTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return customPersonHorizontalTile;
    }));
  }

  /// Enable desktop mode before testing this widget.
  /// Functional test cases for Custom Person Horizontal Tile
  group('Custom Person Horizontal Tile widget Test', () {
    final customPersonHorizontalTile = CustomPersonHorizontalTile();
    // Test Case to check  is Custom Person Horizontal Tile displayed or not
    testWidgets('Test Case to check Custom Person Horizontal Tile is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          customPersonHorizontalTile: customPersonHorizontalTile ));
      expect(find.byType(CustomPersonHorizontalTile), findsOneWidget);
    });
  });
}
