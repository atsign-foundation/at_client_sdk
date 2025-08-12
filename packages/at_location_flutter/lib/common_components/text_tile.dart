import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:flutter/material.dart';

class TextTile extends StatelessWidget {
  final String? title;
  final IconData? icon;
  const TextTile({Key? key, this.title, this.icon}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        icon != null ? Icon(icon) : const SizedBox(),
        const SizedBox(width: 10),
        title != null
            ? Text(title!, style: CustomTextStyles().darkGrey16)
            : const SizedBox()
      ],
    );
  }
}
