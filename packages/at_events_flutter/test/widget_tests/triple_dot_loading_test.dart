import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_events_flutter/common_components/triple_dot_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget typingIndicator}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return typingIndicator;
    }));
  }

  /// Functional test cases for Typing Indicator Widget
  group('Typing Indicator Widget Tests:', () {
    // Test Case to Check Typing Indicator is displayed
    const typingIndicator = TypingIndicator();
    testWidgets("Typing Indicator is displayed", (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(typingIndicator: typingIndicator));
      expect(find.byType(TypingIndicator), findsOneWidget);
    });
  });
}
