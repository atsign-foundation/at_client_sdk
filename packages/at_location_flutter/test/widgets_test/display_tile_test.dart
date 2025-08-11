import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_location_flutter/common_components/display_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget displayTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return displayTile;
    }));
  }

  /// Functional test cases for [displayTile]
  group('Display Tile widget Tests:', () {
    const displayTile = DisplayTile(
      title: 'title',
      atsignCreator: 'atsignCreator',
      subTitle: 'subTitle',
      semiTitle: 'semi title',
      invitedBy: 'invited by',
      number: 25,
    );
    // Test case to identify display tile is used in screen or not
    testWidgets("Test case to identify display tile is used in screen or not",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(displayTile: displayTile));

      expect(find.byType(DisplayTile), findsOneWidget);
    });

    // Test case to check display tile strings other than required fields are given
    testWidgets(
        'Test case to check display tile strings other than required fields are given',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(displayTile: displayTile));

      expect(displayTile.semiTitle, 'semi title');
      expect(displayTile.invitedBy, 'invited by');
    });

    // Test case to check display tile number is given
    testWidgets('Test case to check display tile number is given',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(displayTile: displayTile));
      expect(displayTile.number, 25);
    });
  });
}
