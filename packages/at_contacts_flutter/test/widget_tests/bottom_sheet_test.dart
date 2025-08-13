import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget bottomSheet}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return bottomSheet;
    }));
  }

  /// Functional test cases for Bottom Sheet
  group('Bottom Sheet widget Tests:', () {
    // Test case to identify Bottom Sheet is used in screen or not
    testWidgets("Bottom Sheet widget is used and shown on screen",
        (WidgetTester tester) async {
      final bottomSheet = BottomSheet(
          onClosing: () {},
          builder: (BuildContext context) {
            return Container();
          });
      await tester
          .pumpWidget(wrapWidgetWithMaterialApp(bottomSheet: bottomSheet));

      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });
}
