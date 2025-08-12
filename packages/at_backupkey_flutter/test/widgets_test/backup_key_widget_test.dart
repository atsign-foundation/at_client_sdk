import 'package:at_backupkey_flutter/at_backupkey_flutter.dart';
import 'package:at_backupkey_flutter/utils/size_config.dart';

import '../test_material_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget backupKeyWidget}) {
    return TestMaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          SizeConfig().init(context);
          return Scaffold(body: Container(child: backupKeyWidget));
        },
      ),
    );
  }

  /// Functional test cases for BackupKey Widget
  group('BackupKey Widget Tests:', () {
    final backupKeyWidget = BackupKeyWidget(
      atsign: 'bluebellrelated86',
      buttonText: 'Click here',
      iconColor: Colors.purple,
      buttonColor: Colors.white,
    );
    // Test case to check backupkey widget is displayed
    testWidgets('BackupKey widget is used', (WidgetTester tester) async {
      await tester.pumpWidget(
          wrapWidgetWithMaterialApp(backupKeyWidget: backupKeyWidget));
      expect(find.byType(BackupKeyWidget), findsOneWidget);
    });
    // Test case to identify atsign text
    testWidgets("Identify atsign text", (WidgetTester tester) async {
      await tester.pumpWidget(
          wrapWidgetWithMaterialApp(backupKeyWidget: backupKeyWidget));
      expect(backupKeyWidget.atsign, 'bluebellrelated86');
    });
    // Test case to identify button text
    testWidgets("Identify button text", (WidgetTester tester) async {
      await tester.pumpWidget(
          wrapWidgetWithMaterialApp(backupKeyWidget: backupKeyWidget));
      expect(backupKeyWidget.buttonText, 'Click here');
    });
    // Test case to check icon Color
    testWidgets('Test case to check icon color', (WidgetTester tester) async {
      await tester.pumpWidget(
          wrapWidgetWithMaterialApp(backupKeyWidget: backupKeyWidget));
      expect(backupKeyWidget.iconColor, Colors.purple);
    });
    // Test case to check button Color
    testWidgets('Test case to check button color', (WidgetTester tester) async {
      await tester.pumpWidget(
          wrapWidgetWithMaterialApp(backupKeyWidget: backupKeyWidget));
      expect(backupKeyWidget.buttonColor, Colors.white);
    });
  });
}
