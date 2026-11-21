import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:example/walkthrough.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Catalogue: features/at_client_flutter/registrar_api_key.feature
void main() {
  testWidgets(
    'Activating a new atSign with no registrar API key given says where to '
    'get one',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onboard(context),
                child: const Text('activate'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('activate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byType(AtSignSelectionDialog),
        findsNothing,
        reason:
            'the activation never starts, so nothing reaches the '
            'registrar',
      );
      expect(find.textContaining('my.atsign.com'), findsOneWidget);
      expect(find.textContaining('REGISTRAR_API_KEY'), findsOneWidget);
    },
  );
}
