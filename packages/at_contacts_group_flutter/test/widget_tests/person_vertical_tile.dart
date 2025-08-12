import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/person_vertical_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp(
      {required Widget customPersonVerticalTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return customPersonVerticalTile;
    }));
  }

  /// Enable desktop mode before testing this widget.
  /// Functional test cases for Custom Person Vertical Tile
  group('Custom Person Vertical Tile widget Test', () {
    const customPersonVerticalTile = CustomPersonVerticalTile();
    // Test Case to check  is Custom Person Vertical Tile displayed or not
    testWidgets('Test Case to check Custom Person Vertical Tile is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          customPersonVerticalTile: customPersonVerticalTile));
      expect(find.byType(CustomPersonVerticalTile), findsOneWidget);
    });
  });
}
