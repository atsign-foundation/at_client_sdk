import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/desktop_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget desktopHeader}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: desktopHeader);
    }));
  }
  
  /// Enable desktop mode before testing this widget.
  /// Functional test cases for desktop header
  group('Desktop header widget Test', () {
    final desktopHeader= DesktopHeader(onBackTap: (){},);
    // Test Case to check  is desktop header displayed or not
    testWidgets(
        'Test Case to check desktop header is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(desktopHeader:desktopHeader));
      expect(find.byType(DesktopHeader), findsOneWidget);
    });
  });
}
