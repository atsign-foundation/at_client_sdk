import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_theme_flutter/at_theme_flutter.dart';
// ignore: library_prefixes
import 'package:at_theme_flutter/src/app_theme.dart' as appTheme;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget themeSettingPage}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return themeSettingPage;
    }));
  }

  /// Functional test cases for Theme Setting Page
  group('Theme Setting Page Tests:', () {
    // Test Case to Check Theme Mode Card is displayed
    final themeSettingPage = ThemeSettingPage(
        currentAppTheme: appTheme.AppTheme.from(),
        primaryColors: const [Colors.blue, Colors.pink]);
    testWidgets("Theme Setting Page is displayed", (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrapWidgetWithMaterialApp(themeSettingPage: themeSettingPage));
      expect(find.byType(ThemeSettingPage), findsOneWidget);
    });
  });
}
