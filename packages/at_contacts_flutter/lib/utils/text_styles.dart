import 'package:at_contacts_flutter/utils/colors.dart';
import 'package:flutter/material.dart';

import 'package:at_common_flutter/services/size_config.dart';

/// Text styles used in the package
class CustomTextStyles {
  CustomTextStyles._();
  static final CustomTextStyles _instance = CustomTextStyles._();
  factory CustomTextStyles() => _instance;

  static TextStyle primaryBold18 = TextStyle(
    color: ColorConstants.fontPrimary,
    fontSize: 18.toFont,
    fontWeight: FontWeight.w700,
  );

  static TextStyle primaryRegular16 = TextStyle(
      color: ColorConstants.fontPrimary,
      fontSize: 16.toFont,
      fontWeight: FontWeight.normal);

  static TextStyle secondaryRegular12 = TextStyle(
      color: ColorConstants.fontSecondary,
      fontSize: 12.toFont,
      fontWeight: FontWeight.normal);

  static TextStyle blueRegular14 = TextStyle(
      color: ColorConstants.appBarCloseColor,
      fontSize: 14.toFont,
      fontWeight: FontWeight.normal);

  static TextStyle whiteBold16 = TextStyle(
    color: Colors.white,
    fontSize: 16.toFont,
    fontWeight: FontWeight.w700,
  );

  static TextStyle primaryMedium14 = TextStyle(
    color: ColorConstants.fontPrimary,
    fontSize: 14.toFont,
    fontWeight: FontWeight.w500,
  );

  static TextStyle secondaryRegular16 = TextStyle(
      color: ColorConstants.fontSecondary,
      fontSize: 16.toFont,
      fontWeight: FontWeight.normal);

  static TextStyle primaryBold16 = TextStyle(
    color: ColorConstants.fontPrimary,
    fontSize: 16.toFont,
    fontWeight: FontWeight.w700,
  );

  // desktop text styles
  static TextStyle desktopPrimaryRegular24 = const TextStyle(
    color: Colors.black,
    fontSize: 24,
    letterSpacing: 0.1,
    fontWeight: FontWeight.w600,
  );

  static TextStyle primaryNormal20 = TextStyle(
      color: ColorConstants.fontPrimary,
      fontSize: 20.toFont,
      letterSpacing: 0.1,
      fontWeight: FontWeight.normal);

  static TextStyle desktopSecondaryRegular18 = const TextStyle(
      color: ColorConstants.fontSecondary,
      fontSize: 18,
      letterSpacing: 0.1,
      fontWeight: FontWeight.normal);

  static TextStyle blueNormal20 = TextStyle(
      color: ColorConstants.blueText,
      fontSize: 20.toFont,
      letterSpacing: 0.1,
      fontWeight: FontWeight.normal);

  static TextStyle whiteBold({int size = 16}) => TextStyle(
        color: Colors.white,
        fontSize: size.toFont,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w700,
      );
}
