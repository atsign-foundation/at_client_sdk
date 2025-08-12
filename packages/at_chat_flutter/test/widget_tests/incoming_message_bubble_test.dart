// import 'package:at_chat_flutter/models/message_model.dart';
import 'package:at_chat_flutter/models/message_model.dart';
import 'package:at_chat_flutter/utils/colors.dart';
import 'package:at_chat_flutter/widgets/contacts_initials.dart';
import 'package:at_chat_flutter/widgets/incoming_message_bubble.dart';
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_material_app.dart';

void main() {
  Widget wrapWidgetWithMaterialApp({required Widget incomingMessageBubble}) {
    return TestMaterialApp(home: Builder(builder: (BuildContext context) {
      SizeConfig().init(context);
      return incomingMessageBubble;
    }));
  }

  /// Functional test cases for IncomingMessageBubble
  group('IncomingMessageBubble widget Tests:', () {
    // Test case to identify incoming message bubble is used in screen or not
    testWidgets("Incoming message bubble widget is used and shown on screen",
        (WidgetTester tester) async {
      const incomingMessageBubble = IncomingMessageBubble();
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          incomingMessageBubble: incomingMessageBubble));

      expect(find.byType(IncomingMessageBubble), findsOneWidget);
    });

    // Test case to identify incoming message has text
    testWidgets("Check message in incoming message bubble",
        (WidgetTester tester) async {
      Message message = Message(id: '1', message: 'Hi');
      final incomingMessageBubble = IncomingMessageBubble(
        message: message,
      );
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          incomingMessageBubble: incomingMessageBubble));
      expect(incomingMessageBubble.message, message);
    });

    testWidgets("Color of button is button default color",
        (WidgetTester tester) async {
      const incomingMessageBubble = IncomingMessageBubble(
        color: CustomColors.defaultColor,
      );
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          incomingMessageBubble: incomingMessageBubble));
      final container = tester
          .widget<IncomingMessageBubble>(find.byType(IncomingMessageBubble));
      expect(
        container.color,
        CustomColors.defaultColor,
      );
    });

    // Test case to identify color of avatar in incoming message bubble
    testWidgets("Color of avatar in incoming message bubble",
        (WidgetTester tester) async {
      const incomingMessageBubble = IncomingMessageBubble();
      await tester.pumpWidget(wrapWidgetWithMaterialApp(
          incomingMessageBubble: incomingMessageBubble));
      final contactInitial =
          tester.widget<ContactInitial>(find.byType(ContactInitial));
      final avatarColor = contactInitial.backgroundColor;
      expect(
        avatarColor,
        CustomColors.defaultColor,
      );
    });
  });
}
