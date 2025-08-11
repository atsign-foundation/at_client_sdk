import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_custom_person_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget desktopCustomPersonTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return desktopCustomPersonTile;
    }));
  }

  /// Enable desktop mode before testing this widget.
  /// Functional test cases for desktop custom person tile
  group('Desktop custom person tile widget Test', () {
    const desktopCustomPersonTile = DesktopCustomPersonVerticalTile();
    // Test Case to check  is desktop custom person tile displayed or not
    testWidgets('Test Case to check desktop custom person tile is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          desktopCustomPersonTile: desktopCustomPersonTile));
      expect(find.byType(DesktopCustomPersonVerticalTile), findsOneWidget);
    });
  });
}
