import 'dart:developer';

import 'package:at_chat_flutter/utils/colors.dart';
import 'package:at_chat_flutter/widgets/button_widget.dart';
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget buttonWidget}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return buttonWidget;
    }));
  }

  /// Functional test cases for ButtonWidget
  group('Button widget Tests:', () {
    // variable widget to be tested in each case
    final buttonWidget = ButtonWidget(
      onPress: () {
        log('clicked on this button');
      },
      colorButton: CustomColors.defaultColor,
      textButton: 'Click here',
      borderRadius: const BorderRadius.all(
        Radius.circular(5.0),
      ),
    );

    // Test case to identify button is used in screen or not
    testWidgets("Button widget is used and shown on screen",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(buttonWidget: buttonWidget));

      expect(find.byType(ButtonWidget), findsOneWidget);
    });

    // Test case to check button string is given
    testWidgets("Button text displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(buttonWidget: buttonWidget));
      expect(find.text('Click here'), findsOneWidget);
    });

    // Test case to check onPress functionality
    testWidgets("OnPress is given an action", (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(buttonWidget: buttonWidget));
      expect(buttonWidget.onPress!.call(), null);
    });

    // Test case to check button BorderRadius
    testWidgets("BorderRadius of button widget as circular",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(buttonWidget: buttonWidget));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      final borderRadius = decoration.borderRadius as BorderRadius;
      expect(borderRadius.bottomLeft, const Radius.circular(5.0));
      expect(borderRadius.topLeft, const Radius.circular(5.0));
      expect(borderRadius.bottomRight, const Radius.circular(5.0));
      expect(borderRadius.topRight, const Radius.circular(5.0));
    });

    // Test case to check button Color
    testWidgets("Color of button is button default color",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(buttonWidget: buttonWidget));
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(
        decoration.color,
        CustomColors.defaultColor,
      );
    });
  });
}
