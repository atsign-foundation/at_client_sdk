import 'dart:typed_data';

import 'package:at_chat_flutter/models/message_model.dart';
import 'package:at_chat_flutter/utils/colors.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_chat_flutter/widgets/contacts_initials.dart';
import 'package:flutter/material.dart';

class IncomingMessageBubble extends StatefulWidget {
  final Message? message;
  final Color color;
  final Color avatarColor;

  const IncomingMessageBubble(
      {Key? key,
      this.message,
      this.color = CustomColors.incomingMessageColor,
      this.avatarColor = CustomColors.defaultColor})
      : super(key: key);

  @override
  State<IncomingMessageBubble> createState() => _IncomingMessageBubbleState();
}

class _IncomingMessageBubbleState extends State<IncomingMessageBubble> {
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Flex(
      direction: Axis.horizontal,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20.toWidth,
        ),
        Container(
          height: 45.toFont,
          width: 45.toFont,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(45.toWidth),
          ),
          child: ContactInitial(
            initials: widget.message?.sender ?? '@',
            backgroundColor: widget.avatarColor,
          ),
        ),
        SizedBox(
          width: 15.toWidth,
        ),
        Container(
          padding: EdgeInsets.all(16.toHeight),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(10.toWidth),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 170.toWidth),
            child: _buildContentMessage(),
          ),
        ),
      ],
    );
  }

  Widget _buildContentMessage() {
    if (widget.message?.contentType == MessageContentType.image) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 165.toWidth),
        child: Image.memory(widget.message?.imageData ?? Uint8List(0)),
      );
    } else {
      return Text(
        widget.message?.message ?? ' ',
        textAlign: TextAlign.right,
        maxLines: 3,
      );
    }
  }
}
