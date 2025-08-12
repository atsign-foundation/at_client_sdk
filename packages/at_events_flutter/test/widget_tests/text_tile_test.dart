import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/text_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget textTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return textTile;
    }));
  }

  /// Functional test cases for Text Tile Widget
  group('Text Tile Widget Tests:', () {
    // Test Case to Check Text Tile is displayed
    const textTile = TextTile();
    testWidgets("Text Tile is displayed", (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(textTile: textTile));
      expect(find.byType(TextTile), findsOneWidget);
    });
  });
}
