import 'dart:developer';

import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_location_flutter/common_components/tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget _wrapWidgetWithMaterialApp({required Widget tasks}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: tasks,
            )
          ],
        ),
      );
    }));
  }

  /// Functional test cases for [tasks]
  group('Tasks widget Tests:', () {
    final tasks = Tasks(
      task: 'Tasks',
      icon: Icons.clear,
      onTap: () {
        log('OnPress action is given');
      },
      angle: 90.0,
    );
    // Test case to identify Tasks is used in screen or not
    testWidgets("Test case to identify Tasks is used in screen or not",
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(tasks: tasks));

      expect(find.byType(Tasks), findsOneWidget);
    });
    // Test case to identify Tasks is used in screen or not
    testWidgets("Test case to identify Tasks is used in screen or not",
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrapWidgetWithMaterialApp(tasks: tasks));

      expect(tasks.angle, 90.0);
    });
  });
}
