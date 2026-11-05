import 'package:flutter_test/flutter_test.dart';

import 'package:dockerstats/main.dart';

void main() {
  testWidgets('launch screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const DockerstatsApp());
    expect(
      find.text('Live docker stats over the Atsign Protocol'),
      findsOneWidget,
    );
    expect(find.text('Login with existing atSign'), findsOneWidget);
  });
}
