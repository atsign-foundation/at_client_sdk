import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_invitation_flutter/widgets/share_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget shareDialog}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return shareDialog;
    }));
  }

  /// Functional test cases for Share Dialog Widget
  group('Share Dialog Widget Tests:', () {
    const shareDialog = ShareDialog(
      currentAtsign: '@bluebellrelated86',
      uniqueID: '25',
      passcode: '25032511',
      webPageLink: 'url for the site',
    );
    // Test Case to Check Share Dialog is displayed
    testWidgets("Share Dialog is displayed", (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(shareDialog: shareDialog));
      expect(find.byType(ShareDialog), findsOneWidget);
    });
    // Test case to check current atsign is given
    testWidgets("Test case to check current atsign is given",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(shareDialog: shareDialog));
      expect(shareDialog.currentAtsign, '@bluebellrelated86');
    });
    // Test case to check uniqueId given
    testWidgets("Test case to check unique id is given",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(shareDialog: shareDialog));
      expect(shareDialog.uniqueID, '25');
    });
    // Test case to check passcode is given
    testWidgets("Test case to check passcode is given",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(shareDialog: shareDialog));
      expect(shareDialog.passcode, '25032511');
    });
    // Test case to check web page link is given
    testWidgets("Test case to check web page link is given",
        (WidgetTester tester) async {
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(shareDialog: shareDialog));
      expect(shareDialog.webPageLink, 'url for the site');
    });
  });
}
