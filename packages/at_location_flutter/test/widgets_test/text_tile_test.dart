import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_location_flutter/common_components/text_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget textTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: Container(child: textTile));
    }));
  }

  /// Functional test cases for [textTile]
  group('Text tile widget Tests:', () {
    // Test case to identify Text tile is used in screen or not
    testWidgets("Test case to identify Text tile is used in screen or not",
        (WidgetTester tester) async {
      const textTile = TextTile();
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(textTile: textTile));

      expect(find.byType(TextTile), findsOneWidget);
    });

    // Test case to identify Text tile bg color and icon color is given
    testWidgets("Test case to identify Text tile title is given",
        (WidgetTester tester) async {
      const textTile = TextTile(
        title: 'Text Tile Title',
      );
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(textTile: textTile));
      expect(textTile.title, 'Text Tile Title');
    });
    // Test case to identify Text tile widget icon is given
    testWidgets("Test case to identify Text tile widget icon is given",
        (WidgetTester tester) async {
      const textTile = TextTile(
        icon: Icons.add,
      );
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(textTile: textTile));
      expect(textTile.icon, Icons.add);
    });
  });
}
