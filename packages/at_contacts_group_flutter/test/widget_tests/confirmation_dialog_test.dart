import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget confirmationDialog}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return confirmationDialog;
    }));
  }

  /// Functional test cases for confirmation dialog
  group('Confirmation Dialog Widget Test', () {
    final confirmationDialog = ConfirmationDialog(
        heading: 'heading',
        title: 'title',
        onYesPressed: () {
          log('Onpress is given an action');
        });
    // Test Case to check confirmation dialog is displayed or not
    testWidgets('Test Case to confirmation dialog is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(confirmationDialog: confirmationDialog));
      expect(find.byType(ConfirmationDialog), findsOneWidget);
    });

    // Test case to check heading is given
    testWidgets("Heading is given", (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(confirmationDialog: confirmationDialog));
      expect(find.text('heading'), findsOneWidget);
    });

    // Test case to check title is given
    testWidgets("Title is given", (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(confirmationDialog: confirmationDialog));
      expect(find.text('title'), findsOneWidget);
    });

    // Test case to check onPress functionality
    testWidgets("OnPress is given an action", (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(confirmationDialog: confirmationDialog));
      expect(confirmationDialog.onYesPressed.call(), null);
    });
  });
}
