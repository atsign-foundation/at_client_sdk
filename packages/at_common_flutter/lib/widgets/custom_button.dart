import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_common_flutter/utils/colors.dart';
import 'package:at_common_flutter/utils/text_styles.dart';

/// A custom button to use the theme colors and common app functionalities.
class CustomButton extends StatelessWidget {
  /// defines the function to execute on press of this button.
  final Function()? onPressed;

  /// a string to display on this button.
  final String buttonText;

  /// sets the height of the button.
  final double? height;

  /// sets the width of the button.
  final double? width;

  /// sets the fill color of the button.
  final Color buttonColor;

  /// sets the font color for [buttonText] text
  final Color fontColor;

  /// to give radius to button border
  /// If null, 30 will be assigned as [borderRadius]
  final double? borderRadius;

  const CustomButton(
      {Key? key,
      this.onPressed,
      this.buttonText = '',
      this.height,
      this.width,
      this.buttonColor = Colors.black,
      this.fontColor = ColorConstants.fontPrimary,
      this.borderRadius})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: Container(
        width: width ?? 158.toWidth,
        height: height ?? (50.toHeight),
        padding: EdgeInsets.symmetric(horizontal: 10.toWidth),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius ?? 30.toWidth),
            color: buttonColor),
        child: Center(
          child: Text(
            buttonText,
            textAlign: TextAlign.center,
            style: CustomTextStyles.primaryBold16(fontColor),
          ),
        ),
      ),
    );
  }
}
