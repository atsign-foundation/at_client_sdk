import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_notify_flutter/screens/notify_screen.dart';
import 'package:at_notify_flutter/services/notify_service.dart';

import '../test_material_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget notifyScreen}) {
    return TestMaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          SizeConfig().init(context);
          return Scaffold(body: Container(child: notifyScreen));
        },
      ),
    );
  }

  /// Functional test cases for Notify screen
  group('Notify Screen Tests:', () {
    NotifyService notifyService=NotifyService();
    final notifyScreen = NotifyScreen(
      notifyService: notifyService,
      atSign: '@bluebellrelated86',
    );
    // Test case to check notify screen is displayed
    testWidgets('Notify Screen is used', (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(notifyScreen: notifyScreen));
      expect(find.byType(NotifyScreen), findsOneWidget);
    });
     // Test case to check atsign is given
    testWidgets('Test case to check atsign is given', (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(notifyScreen: notifyScreen));
      expect(notifyScreen.atSign,'@bluebellrelated86');
    });
     // Test case to check notify service is given
    testWidgets('Test case to check notify service is given', (WidgetTester tester) async {
      await tester
          .pumpWidget(_wrapWidgetWithMaterialApp(notifyScreen: notifyScreen));
      expect(notifyScreen.notifyService,notifyService);
    });
  });
}
