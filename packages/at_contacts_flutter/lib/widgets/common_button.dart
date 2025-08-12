import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

class CommonButton extends StatelessWidget {
  final String title;
  final Function() onTap;
  final double? border, height, width, fontSize;
  final Color? color;
  final bool removePadding;
  final Color? textColor;
  final Widget? leading;
  const CommonButton(
    this.title,
    this.onTap, {
    Key? key,
    this.border,
    this.color,
    this.height,
    this.width,
    this.removePadding = false,
    this.fontSize,
    this.textColor,
    this.leading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var deviceTextFactor = MediaQuery.of(context).textScaler.scale(20) / 20;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width ?? 120.toWidth,
        height: height ?? 45.toHeight * deviceTextFactor,
        padding: EdgeInsets.symmetric(
          vertical: removePadding ? 0 : 10.toHeight,
          horizontal: removePadding ? 0 : 30.toWidth,
        ),
        decoration: BoxDecoration(
          color: color ?? Colors.black,
          borderRadius: BorderRadius.circular(border ?? 20.toFont),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading ?? const SizedBox(),
              SizedBox(
                width: leading != null ? 5 : 0,
              ),
              Text(
                title,
                style: TextStyle(
                  color: textColor ?? Colors.white,
                  fontSize: fontSize ?? 15.toFont,
                  letterSpacing: 0.1,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
