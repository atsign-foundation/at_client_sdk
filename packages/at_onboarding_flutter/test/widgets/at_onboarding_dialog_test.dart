import 'package:at_onboarding_flutter/at_onboarding_flutter.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_button.dart';
import 'package:at_onboarding_flutter/widgets/at_onboarding_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _appWithDialog({
    ThemeData? theme,
    required Function(BuildContext context) onTap,
  }) {
    return MaterialApp(
      theme: theme,
      home: Material(
        child: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: InkWell(
                  key: const Key("InkWell"),
                  onTap: () {
                    onTap(context);
                  },
                  child: const SizedBox(
                    height: 20,
                    width: 20,
                    child: Text("Tap Me"),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      localizationsDelegates: const [
        AtOnboardingLocalizations.delegate,
      ],
    );
  }

  group('at_onboarding_dialog Tests:', () {
    testWidgets('show dialog default', (tester) async {
      await tester.pumpWidget(_appWithDialog(
        onTap: (context) {
          AtOnboardingDialog.showError(
            context: context,
            message: "Error message",
          );
        },
      ));
      await tester.tap(find.byKey(const Key("InkWell")));
      await tester.pumpAndSettle();
      // Expect to find dialog title on screen.
      expect(find.text('Notice'), findsOneWidget);
    });

    testWidgets('show dialog title custom', (tester) async {
      await tester.pumpWidget(_appWithDialog(
        onTap: (context) {
          AtOnboardingDialog.showError(
            context: context,
            title: "Title",
            message: "Error message",
          );
        },
      ));
      await tester.tap(find.byKey(const Key("InkWell")));
      await tester.pumpAndSettle();
      // Expect to find dialog title on screen.
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Error message'), findsOneWidget);
    });

    testWidgets('tap Cancel dialog', (tester) async {
      await tester.pumpWidget(_appWithDialog(
        onTap: (context) {
          AtOnboardingDialog.showError(
            context: context,
            message: "Error message",
          );
        },
      ));

      await tester.tap(find.byKey(const Key("InkWell")));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AtOnboardingSecondaryButton));
      await tester.pumpAndSettle();
      // Expect don't find the title dialog on screen.
      expect(find.text('Error'), findsNothing);
    });

    testWidgets('handle function Cancel dialog', (tester) async {
      bool _checkShowDialog = true;

      await tester.pumpWidget(_appWithDialog(
        onTap: (context) {
          AtOnboardingDialog.showError(
            context: context,
            message: "Error message",
            onCancel: () {
              _checkShowDialog = false;
            },
          );
        },
      ));

      await tester.tap(find.byKey(const Key("InkWell")));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AtOnboardingSecondaryButton));
      await tester.pumpAndSettle();

      // Expect run function
      expect(_checkShowDialog, false);
    });
  });
}
