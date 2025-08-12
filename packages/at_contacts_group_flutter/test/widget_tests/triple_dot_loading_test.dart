import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/triple_dot_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget typingIndicator}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(body: Container(child: typingIndicator));
    }));
  }

  /// Functional test cases for Typing Indicator
  group('Typing Indicator widget Test', () {
    const typingIndicator = TypingIndicator();
    // Test Case to check  is Typing Indicator displayed or not
    testWidgets('Test Case to check Typing Indicator is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(typingIndicator: typingIndicator));
      expect(find.byType(TypingIndicator), findsOneWidget);
    });
  });
}
