import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_contacts_group_flutter/widgets/contacts_selction_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp(
      {required Widget contactSelectionBottomSheet}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return contactSelectionBottomSheet;
    }));
  }

  /// Functional test cases for contact selection bottom sheet
  group('Contact selection bottom sheet widget Test', () {
    const contactSelectionBottomSheet = ContactSelectionBottomSheet();
    // Test Case to check  is contact selection bottom sheet displayed or not
    testWidgets(
        'Test Case to check contact selection bottom sheet is displayed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(
          contactSelectionBottomSheet: contactSelectionBottomSheet));
      expect(find.byType(ContactSelectionBottomSheet), findsOneWidget);
    });
  });
}
