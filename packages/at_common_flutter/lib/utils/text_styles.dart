import 'package:at_common_flutter/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:at_common_flutter/services/size_config.dart';

/// Common text styles used in the widgets.
class CustomTextStyles {
  CustomTextStyles._();
  static final CustomTextStyles _instance = CustomTextStyles._();
  factory CustomTextStyles() => _instance;

  static TextStyle primaryBold16(Color fontColor) => TextStyle(
        color: fontColor,
        fontSize: 16.toFont,
        fontWeight: FontWeight.w700,
      );

  static TextStyle primaryBold18 = TextStyle(
    color: ColorConstants.fontPrimary,
    fontSize: 18.toFont,
    fontWeight: FontWeight.w700,
  );
  static TextStyle blueRegular18 = TextStyle(
      color: ColorConstants.appBarCloseColor,
      fontSize: 18.toFont,
      fontWeight: FontWeight.normal);
}
