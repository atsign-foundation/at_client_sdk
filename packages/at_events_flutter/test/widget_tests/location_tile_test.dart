import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/location_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget locationTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return locationTile;
    }));
  }

  /// Functional test cases for Location Tile Widget
  group('Location Tile Widget Tests:', () {
    const locationTile = LocationTile(
      title: 'Title',
      subTitle: 'SubTitle',
    );
    // Test Case to Check Location Tile is displayed
    testWidgets("Location Tile is displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(locationTile: locationTile));
      expect(find.byType(LocationTile), findsOneWidget);
    });
    // Test case to check button string is given
    testWidgets("Button text displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(locationTile: locationTile));
      expect(find.text('Title'), findsOneWidget);
    });
    // Test case to check button string is given
    testWidgets("Button text displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(locationTile: locationTile));
      expect(find.text('SubTitle'), findsOneWidget);
    });
  });
}
