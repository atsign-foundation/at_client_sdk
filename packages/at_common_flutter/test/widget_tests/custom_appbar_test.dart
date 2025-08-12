import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_common_flutter/utils/text_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget homeWidget({required Widget home}) {
    return TestMaterialApp(home: home);
  }

  group('CustomAppBar Widget tests', () {
    testWidgets('CustomAppBar with title enabled', (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
      )));
      final appBar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));
      expect(appBar.titleText, 'Welcome Screen');
      expect(find.text('Welcome Screen'), findsOneWidget);
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('CustomAppBa with title disabled', (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: false,
      )));
      final appBar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));

      expect(appBar.titleText, 'Welcome Screen');
      expect(find.text('Welcome Screen'), findsNothing);
    });
    testWidgets('CustomAppBar with leading Icons enabled',
        (WidgetTester tester) async {
      var uniqueKey = const Key('testIcon');
      await tester.pumpWidget(homeWidget(
          home: CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        leadingIcon: IconButton(
            key: uniqueKey, icon: const Icon(Icons.menu), onPressed: () {}),
        showLeadingIcon: true,
      )));
      final appBar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));
      expect(appBar.showLeadingIcon, true);
      expect(find.byKey(uniqueKey), findsOneWidget);

      await tester.pumpWidget(homeWidget(
          home: const CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        showLeadingIcon: true,
      )));
      expect(find.byKey(uniqueKey), findsNothing);
    });

    testWidgets('CustomAppBar with leading Icons disabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        showLeadingIcon: false,
      )));
      final appBar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));
      expect(appBar.showLeadingIcon, false);
    });

    testWidgets('CustomAppBar with backbuttons and leading icons enabled',
        (WidgetTester tester) async {
      var uniqueKey = const Key('testIcon');
      await tester.pumpWidget(homeWidget(
          home: CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        leadingIcon: IconButton(
            key: uniqueKey, icon: const Icon(Icons.menu), onPressed: () {}),
        showLeadingIcon: true,
        showBackButton: true,
      )));
      final appBar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));
      expect(appBar.showLeadingIcon, true);
      expect(appBar.showBackButton, true);
      expect(find.byKey(uniqueKey), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.arrow_back), findsOneWidget);
    });

    testWidgets(
        'CustomAppBar with backbuttons enabled and leadingIcons disabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(homeWidget(
          home: const CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        showLeadingIcon: false,
        showBackButton: true,
      )));
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('CustomAppBar with trailing Icons enabled',
        (WidgetTester tester) async {
      var uniqueKey = const Key('testIcon');
      await tester.pumpWidget(homeWidget(
          home: CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        showTrailingIcon: true,
        trailingIcon: Icon(Icons.person_add, key: uniqueKey),
        onTrailingIconPressed: () {
          log('Clicked on trailing');
        },
      )));
      expect(find.byKey(uniqueKey), findsOneWidget);
      final appBar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));
      expect(appBar.onTrailingIconPressed!.call(), null);
    });

    testWidgets('CustomAppBar with trailing Icons disabled',
        (WidgetTester tester) async {
      var uniqueKey = const Key('testIcon');
      await tester.pumpWidget(homeWidget(
          home: CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        showTrailingIcon: false,
        trailingIcon: Icon(Icons.person_add, key: uniqueKey),
      )));
      expect(find.byKey(uniqueKey), findsNothing);
    });

    testWidgets('CustomAppBar with closeOnRight and trailing icons enabled',
        (WidgetTester tester) async {
      var uniqueKey = const Key('testIcon');
      await tester.pumpWidget(homeWidget(
          home: CustomAppBar(
        titleText: 'Welcome Screen',
        showTitle: true,
        showTrailingIcon: true,
        closeOnRight: true,
        trailingIcon: Icon(Icons.person_add, key: uniqueKey),
        onTrailingIconPressed: () {
          log('Trailing icon clicked');
        },
      )));
      expect(find.byKey(uniqueKey), findsNothing);
      final appBar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));
      expect(
          find.byWidgetPredicate((Widget widget) =>
              widget is Text && widget.data == TextStrings().buttonClose),
          findsOneWidget);
      expect(appBar.onTrailingIconPressed!.call(), null);
    });
  });
}
