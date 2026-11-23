import 'package:flutter_test/flutter_test.dart';
import 'package:location_sharing/main.dart';

void main() {
  testWidgets('login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LocationSharingApp());

    expect(
      find.text('Share your live location over the Atsign Protocol'),
      findsOneWidget,
    );
    expect(find.text('Continue with keychain'), findsOneWidget);
    expect(find.text('Onboard from .atKeys file'), findsOneWidget);
  });
}
