import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_custom_person_tile.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp(
      {required Widget desktopPersonVerticalTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return desktopPersonVerticalTile;
    }));
  }

  /// Enable desktop mode before testing this widget.
  /// Functional test cases for desktop person vertical tile
  group('Desktop person vertical tile widget Test', () {
    const desktopPersonVerticalTile = DesktopCustomPersonVerticalTile();
    // Test Case to check  is desktop person vertical tile displayed or not
    testWidgets('Test Case to check desktop person vertical tile is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          desktopPersonVerticalTile: desktopPersonVerticalTile));
      expect(find.byType(DesktopCustomPersonVerticalTile), findsOneWidget);
    });
  });
}
