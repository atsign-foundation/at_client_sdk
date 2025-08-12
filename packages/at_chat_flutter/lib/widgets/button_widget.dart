import 'dart:io';

import 'package:at_chat_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

// ignore: must_be_immutable
class ButtonWidget extends StatelessWidget {
  ButtonWidget({
    Key? key,
    required this.onPress,
    required this.colorButton,
    this.colorBorder = CustomColors.defaultColor,
    this.colorText = Colors.white,
    required this.textButton,
    required this.borderRadius,
    this.height = 45,
    this.marginBottom = 0,
    this.marginRight = 0,
    this.width = double.infinity,
  }) : super(key: key);

  final Function()? onPress;
  final Color colorButton;
  final Color colorBorder;
  final Color colorText;
  final String textButton;
  final BorderRadius borderRadius;
  double width;
  double height;
  double marginBottom;
  double marginRight;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      height += MediaQuery.of(context).padding.bottom / 2;
    }
    return GestureDetector(
      onTap: onPress,
      child: Container(
        alignment: Alignment.center,
        height: height,
        width: width,
        margin: EdgeInsets.only(
          bottom: marginBottom,
          right: marginRight,
        ),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: colorBorder),
          color: colorButton,
        ),
        child: Text(
          textButton,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorText,
          ),
        ),
      ),
    );
  }
}
