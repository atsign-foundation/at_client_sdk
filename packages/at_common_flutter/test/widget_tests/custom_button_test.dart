import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_common_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget homeWidget({required Widget home}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return home;
    }));
  }

  group('CustomButton widget Tests', () {
    testWidgets('CustomButton with text', (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomButton(
        buttonText: 'Enter',
      )));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      expect(customButton.buttonText, 'Enter');
    });

    testWidgets('CustomButton without text', (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(home: const CustomButton()));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      expect(customButton.buttonText, '');
    });

    testWidgets('CustomButton with buttonColor and fontColor passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomButton(
        buttonColor: Colors.orange,
        fontColor: Colors.white,
      )));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      expect(customButton.buttonColor, Colors.orange);
      expect(customButton.fontColor, Colors.white);

      final container = tester.widget<Container>(find.byType(Container));
      final color = (container.decoration as BoxDecoration).color;

      expect(color, Colors.orange);
      expect(
          find.byWidgetPredicate((Widget widget) =>
              widget is Text && widget.style!.color == Colors.white),
          findsOneWidget);
    });

    testWidgets('CustomButton with buttonColor and fontColor not passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(home: const CustomButton()));
      await tester.pumpWidget(homeWidget(home: const CustomButton()));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      expect(customButton.buttonColor, Colors.black);
      expect(customButton.fontColor, ColorConstants.fontPrimary);
    });
    testWidgets('CustomButton with buttonColor passed and fontColor not passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomButton(
        buttonColor: Colors.orange,
      )));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      expect(customButton.buttonColor, Colors.orange);
      expect(customButton.fontColor, ColorConstants.fontPrimary);

      final container = tester.widget<Container>(find.byType(Container));
      final color = (container.decoration as BoxDecoration).color;

      expect(color, Colors.orange);
      expect(
          find.byWidgetPredicate((Widget widget) =>
              widget is Text && widget.style!.color == Colors.white),
          findsNothing);
    });
    testWidgets('CustomButton with buttonColor not passed and fontColor passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomButton(
        fontColor: Colors.red,
      )));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      expect(customButton.buttonColor, Colors.black);
      expect(customButton.fontColor, Colors.red);

      final container = tester.widget<Container>(find.byType(Container));
      final color = (container.decoration as BoxDecoration).color;

      expect(color, Colors.black);
      expect(
          find.byWidgetPredicate((Widget widget) =>
              widget is Text && widget.style!.color == Colors.red),
          findsOneWidget);
    });
    testWidgets('CustomButton with onPressed', (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(home: CustomButton(
        onPressed: () {
          log('clicked on this button');
        },
      )));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      expect(customButton.onPressed!.call(), null);
    });

    testWidgets('CustomButton with onPressed not called',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(home: const CustomButton()));
      final customButton =
          tester.widget<CustomButton>(find.byType(CustomButton));
      await tester.tap(find.byType(CustomButton));
      expect(customButton.onPressed, null);
    });
  });
}
