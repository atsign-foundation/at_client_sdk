import 'package:at_ui_flutter/at_ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtTheme and Token Injection Tests', () {
    testWidgets('AtTheme.lightTheme successfully injects all design tokens', (
      WidgetTester tester,
    ) async {
      //Build a dummy widget tree.
      await tester.pumpWidget(
        MaterialApp(
          theme: AtTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                // Attempt to read each token from the theme.
                final atColors = Theme.of(context).extension<AtColors>();
                final atElevation = Theme.of(context).extension<AtElevation>();
                final atRadius = Theme.of(context).extension<AtRadius>();
                final atSpacing = Theme.of(context).extension<AtSpacing>();
                final atTypography = Theme.of(
                  context,
                ).extension<AtTypography>();

                // Verify that each token is not null, confirming successful injection.
                expect(
                  atColors,
                  isNotNull,
                  reason: 'AtColors should be injected into the theme',
                );
                expect(
                  atElevation,
                  isNotNull,
                  reason: 'AtElevation should be injected into the theme',
                );
                expect(
                  atRadius,
                  isNotNull,
                  reason: 'AtRadius should be injected into the theme',
                );
                expect(
                  atSpacing,
                  isNotNull,
                  reason: 'AtSpacing should be injected into the theme',
                );
                expect(
                  atTypography,
                  isNotNull,
                  reason: 'AtTypography should be injected into the theme',
                );

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });
  });
}
