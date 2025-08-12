import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_person_horizontal_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget desktopPersonHorizontalTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return desktopPersonHorizontalTile ;
    }));
  }

  /// Enable desktop mode before testing this widget.
  /// Functional test cases for desktop person horizontal tile
  group('Desktop  person horizontal tile widget Test', () {
    final desktopPersonHorizontalTile = DesktopCustomPersonHorizontalTile();
    // Test Case to check  is desktop person horizontal tile displayed or not
    testWidgets('Test Case to check desktop person horizontal tile is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          desktopPersonHorizontalTile:desktopPersonHorizontalTile ));
      expect(find.byType(DesktopCustomPersonHorizontalTile), findsOneWidget);
    });
  });
}
