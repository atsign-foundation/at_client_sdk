import 'dart:typed_data';

import 'package:at_chat_flutter/models/message_model.dart';
import 'package:at_chat_flutter/utils/colors.dart';
import 'package:at_chat_flutter/utils/dialog_utils.dart';

// ignore: import_of_legacy_library_into_null_safe
import 'package:at_common_flutter/at_common_flutter.dart';
import 'package:at_chat_flutter/widgets/contacts_initials.dart';
import 'package:flutter/material.dart';

class OutgoingMessageBubble extends StatefulWidget {
  final Message? message;
  final Color color;
  final Color avatarColor;
  final Function(String?) deleteCallback;

  const OutgoingMessageBubble(this.deleteCallback,
      {Key? key,
      this.message,
      this.color = CustomColors.outgoingMessageColor,
      this.avatarColor = CustomColors.defaultColor})
      : super(key: key);

  @override
  State<OutgoingMessageBubble> createState() => _OutgoingMessageBubbleState();
}

class _OutgoingMessageBubbleState extends State<OutgoingMessageBubble> {
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return GestureDetector(
      onLongPress: () {
        showBottomSheetDialog(context, () {
          widget.deleteCallback(widget.message?.id);
        });
      },
      child: Flex(
        direction: Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(30.toHeight),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(10.toWidth),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 165.toWidth),
              child: _buildContentMessage(),
            ),
          ),
          SizedBox(
            width: 15.toWidth,
          ),
          Container(
            height: 45.toFont,
            width: 45.toFont,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(45.toWidth),
            ),
            child: ContactInitial(
              initials: widget.message?.sender ?? '@',
            ),
          ),
          SizedBox(
            width: 20.toWidth,
          )
        ],
      ),
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
      );
    }
  }
}
