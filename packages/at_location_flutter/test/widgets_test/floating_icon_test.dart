import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_location_flutter/common_components/floating_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget floatingIcon}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: Container(child: floatingIcon));
    }));
  }

  /// Functional test cases for [floatingIcon]
  group('Floating icon widget Tests:', () {
    // Test case to identify Floating icon is used in screen or not
    testWidgets("Test case to identify Floating icon is used in screen or not",
        (WidgetTester tester) async {
      const floatingIcon = FloatingIcon();
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(floatingIcon: floatingIcon));

      expect(find.byType(FloatingIcon), findsOneWidget);
    });

    // Test case to identify Floating icon bg color and icon color is given
    testWidgets(
        "Test case to identify Floating icon bg color and icon color is given",
        (WidgetTester tester) async {
      const floatingIcon = FloatingIcon(
        bgColor: Colors.white,
        iconColor: Colors.blue,
      );
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(floatingIcon: floatingIcon));

      expect(floatingIcon.bgColor, Colors.white);
      expect(floatingIcon.iconColor, Colors.blue);
    });
    // Test case to identify Floating icon widget icon is given
    testWidgets("Test case to identify Floating icon widget icon is given",
        (WidgetTester tester) async {
      const floatingIcon = FloatingIcon(
        icon: Icons.add,
      );
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(floatingIcon: floatingIcon));
      expect(floatingIcon.icon, Icons.add);
    });
    // Test case to identify Floating icon widget onpressed action is given
    testWidgets(
        "Test case to identify Floating icon widget onpressed action is given",
        (WidgetTester tester) async {
      final floatingIcon = FloatingIcon(
        onPressed: () {
          log('OnPress is given an action');
        },
      );
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(floatingIcon: floatingIcon));
      expect(floatingIcon.onPressed!.call(), null);
    });
  });
}
