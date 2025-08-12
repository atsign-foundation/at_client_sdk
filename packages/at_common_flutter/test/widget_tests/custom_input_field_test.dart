import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget homeWidget({required Widget home}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Material(child: home);
    }));
  }

  group('CustomInputField widget Tests', () {
    testWidgets('CustomInputField with initialValue and passing input',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: CustomInputField(
        initialValue: 'Welcome',
        value: (value) {
          log('onchanged value is $value');
        },
        onSubmitted: (value) {
          log('entered value is $value');
        },
      )));
      final inputField =
          tester.widget<CustomInputField>(find.byType(CustomInputField));
      expect(inputField.textController.text, 'Welcome');
      await tester.showKeyboard(find.byType(CustomInputField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is TextField && widget.controller!.text == 'Welcome'),
          findsOneWidget);
      await tester.enterText(find.byType(CustomInputField), 'I am logged in');
      expect(
          find.byWidgetPredicate((widget) =>
              widget is TextField &&
              widget.controller!.text == 'I am logged in'),
          findsOneWidget);
    });

    testWidgets('CustomInputField with readOnly enabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: CustomInputField(
        isReadOnly: true,
        initialValue: 'Welcome',
      )));
      final inputField =
          tester.widget<CustomInputField>(find.byType(CustomInputField));
      expect(inputField.textController.text, 'Welcome');
      await tester
          .enterText(find.byType(CustomInputField), 'I am logged in')
          .catchError((e) {
        log('editing text throws $e');
      });
    });
    testWidgets('CustomInputField with icon data passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: CustomInputField(
        isReadOnly: true,
        initialValue: 'Welcome',
        icon: Icons.person,
        iconColor: Colors.blue,
        onIconTap: () {
          log('Tapped on icon');
        },
      )));
      final inputField =
          tester.widget<CustomInputField>(find.byType(CustomInputField));
      expect(inputField.iconColor, Colors.blue);
      expect(inputField.onIconTap!.call(), null);
      expect(inputField.icon, Icons.person);
    });

    testWidgets('CustomInputField with icon data not passed',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: CustomInputField(
        isReadOnly: true,
        initialValue: 'Welcome',
      )));
      final inputField =
          tester.widget<CustomInputField>(find.byType(CustomInputField));
      expect(inputField.iconColor == Colors.red, false);
      expect(inputField.icon, null);
      expect(find.byType(Icon), findsNothing);
      expect(inputField.onIconTap, null);
    });
  });
}
