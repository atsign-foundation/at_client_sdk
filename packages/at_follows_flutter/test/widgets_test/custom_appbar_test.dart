import 'package:at_follows_flutter/services/size_config.dart';
import 'package:at_follows_flutter/widgets/custom_appbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget customAppBar}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return customAppBar;
    }));
  }

  /// Functional test cases for Custom App Bar Widget
  group('Custom App Bar Widget Tests:', () {
    // Test Case to Check custom app bar is displayed
    testWidgets("Custom App Bar is displayed", (WidgetTester tester) async {
      final customAppBar = CustomAppBar(title: 'Custom App Bar',);
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(customAppBar: customAppBar));
      expect(find.byType(CustomAppBar), findsOneWidget);
    });
  });
}
