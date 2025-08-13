import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';

class TextTile extends StatelessWidget {
  final String? title;
  final IconData? icon;
  const TextTile({Key? key, this.title, this.icon}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ignore: avoid_unnecessary_containers
    return Container(
      child: Row(
        children: <Widget>[
          icon != null ? Icon(icon) : const SizedBox(),
          const SizedBox(width: 10),
          title != null
              ? Text(title!, style: CustomTextStyles().darkGrey16)
              : const SizedBox()
        ],
      ),
    );
  }
}
