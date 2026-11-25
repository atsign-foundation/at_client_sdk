import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// AtSignSelectionDialog shows a typed Atsign in its canonical form, and
/// offers Continue only for a valid one.
void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // NOTE: the test font draws every glyph a full em wide, so at full
        // scale the dialog's labels overflow its fixed width.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AtSignSelectionDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder atSignField() => find.byType(TextField).first;

  bool continueEnabled(WidgetTester tester) => tester
      .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Continue'))
      .enabled;

  group('Given AtSignSelectionDialog', () {
    testWidgets('when the user types a valid Atsign, then it shows in its '
        'canonical form and Continue is enabled', (tester) async {
      await openDialog(tester);

      await tester.enterText(atSignField(), 'Alice');
      await tester.pump();

      expect(find.text('@alice'), findsOneWidget);
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('when the user types an Atsign that is not valid, then the '
        'text stays as typed and Continue is disabled', (tester) async {
      await openDialog(tester);

      await tester.enterText(atSignField(), 'al ice');
      await tester.pump();

      expect(find.text('al ice'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
