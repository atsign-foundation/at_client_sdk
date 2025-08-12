import 'package:at_follows_flutter/services/size_config.dart';
import 'package:at_follows_flutter/widgets/web_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget webViewScreen}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return webViewScreen;
    }));
  }

  /// Functional test cases for Web view screen
  group('Web view screen Tests:', () {
    // Test Case to Check Web view screen is displayed
    testWidgets("Web view screen is displayed", (WidgetTester tester) async {
      final webViewScreen =
          WebViewScreen(url: 'https://atsign.com', title: 'atsign');
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(webViewScreen: webViewScreen));
      expect(find.byType(WebViewScreen), findsOneWidget);
    });
  });
}
