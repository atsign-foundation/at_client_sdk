import 'package:at_follows_flutter/services/size_config.dart';
import 'package:at_follows_flutter/widgets/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget customErrorDialog}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return customErrorDialog;
    }));
  }

  /// Functional test cases for Custom Error Dialog Widget
  group('Custom Error Dialog Widget Tests:', () {
    // Test Case to Check Custom Error Dialog is displayed
    testWidgets("Custom Error Dialog is displayed", (WidgetTester tester) async {
      final customErrorDialog = CustomErrorDialog(error: 'error');
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(customErrorDialog: customErrorDialog));
      expect(find.byType(CustomErrorDialog), findsOneWidget);
    });
  });
}
