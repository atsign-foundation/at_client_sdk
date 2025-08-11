import 'package:at_events_flutter/utils/text_styles.dart';
import 'package:flutter/material.dart';

class PopButton extends StatelessWidget {
  final String label;
  final TextStyle? textStyle;
  final Function? onTap;
  const PopButton({Key? key, required this.label, this.textStyle, this.onTap})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap as void Function()? ?? () => Navigator.pop(context),
        child: Text(label, style: textStyle ?? CustomTextStyles().orange16));
  }
}
