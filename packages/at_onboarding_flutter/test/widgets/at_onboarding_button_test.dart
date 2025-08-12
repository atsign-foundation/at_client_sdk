import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:at_sync_ui_flutter/at_sync_material.dart';

import '../test_material_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget button}) {
    return TestMaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          return Scaffold(
            body: Container(
              child: button,
            ),
          );
        },
      ),
    );
  }

  /// Functional test cases for primary button
  group('Primary Button Tests:', () {
    const primaryButton = AtOnboardingPrimaryButton(
      child: Text('Click me'),
    );

    // Test case to check custom app bar is is displayed
    testWidgets('Primary button is used', (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(button: primaryButton));
      expect(find.byType(AtOnboardingPrimaryButton), findsOneWidget);
    });

    // Test case to custom app bar title is given
    testWidgets('Test case to check primary button title is given',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(button: primaryButton));
      expect((primaryButton.child as Text).data, 'Click me');
    });
  });

  /// Functional test cases for secondary button
  group('Secondary Button Tests:', () {
    const secondaryButton = AtOnboardingSecondaryButton(
      child: Text('Click me'),
    );

    const secondaryButtonLoading = AtOnboardingSecondaryButton(
      isLoading: true,
      child: Text('Click me'),
    );

    // Test case to check custom app bar is is displayed
    testWidgets('Primary button is used', (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(button: secondaryButton));
      expect(find.byType(AtOnboardingSecondaryButton), findsOneWidget);
    });

    // Test case to custom app bar title is given
    testWidgets('Test case to check primary button title is given',
        (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(button: secondaryButton));
      expect((secondaryButton.child as Text).data, 'Click me');
    });

    testWidgets('Test case to check primary button loading',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(button: secondaryButtonLoading));
      expect(find.byType(AtSyncIndicator), findsOneWidget);
    });
  });
}
