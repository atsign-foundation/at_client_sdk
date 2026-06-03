import 'package:flutter_test/flutter_test.dart';
import 'package:location_sharing/main.dart';

void main() {
  testWidgets('launch screen renders login options', (tester) async {
    await tester.pumpWidget(const LocationSharingApp());

    expect(find.text('Location sharing'), findsOneWidget);
    expect(find.text('Login with existing atSign'), findsOneWidget);
    expect(find.text('Login from .atKeys file'), findsOneWidget);
  });
}
