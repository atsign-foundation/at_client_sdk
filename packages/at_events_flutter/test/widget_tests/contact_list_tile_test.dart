import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/contact_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget contactListTile}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: Container(child: contactListTile));
    }));
  }

  /// Functional test cases for Contact List Tile Widget
  group('Contact List Tile Widget Tests:', () {
    // Test Case to Check Contact List Tile is displayed
    testWidgets("Contact List Tile is displayed", (WidgetTester tester) async {
      final contactListTile = ContactListTile(
        onRemove: () {},
        name: 'Bluebellrealted',
        image: const Icon(Icons.add),
        onAdd: () {},
        onTileTap: () {},
        atSign: '@bluebellralted86',
      );
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(contactListTile: contactListTile));
      expect(find.byType(ContactListTile), findsOneWidget);
    });
  });
}
