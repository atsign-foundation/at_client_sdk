import 'dart:io';

import 'package:flutter/material.dart';

/// A class defined to get dimensions for the screen size displayed,
/// using the proportion of the designed screen size.
class SizeConfig {
  SizeConfig._();

  static final SizeConfig _instance = SizeConfig._();

  factory SizeConfig() => _instance;
  late MediaQueryData _mediaQueryData;
  late double screenWidth;
  late double screenHeight;
  late double blockSizeHorizontal;
  late double blockSizeVertical;
  late double deviceTextFactor;

  late double _safeAreaHorizontal;
  late double _safeAreaVertical;
  late double safeBlockHorizontal;
  late double safeBlockVertical;

  double? profileDrawerWidth;
  late double refHeight;
  late double refWidth;

  double textFactor = 1.0;

  bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 700;

  bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 700 &&
      MediaQuery.of(context).size.width < 1200;
  bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1200;

  void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    refHeight = 812;
    refWidth = 375;

    deviceTextFactor = _mediaQueryData.textScaler.scale(20) / 20;

    // print("height is::: $screenHeight");

    if (screenHeight < 1200) {
      blockSizeHorizontal = screenWidth / 100;
      blockSizeVertical = screenHeight / 100;

      _safeAreaHorizontal =
          _mediaQueryData.padding.left + _mediaQueryData.padding.right;
      _safeAreaVertical =
          _mediaQueryData.padding.top + _mediaQueryData.padding.bottom;
      safeBlockHorizontal = (screenWidth - _safeAreaHorizontal) / 100;
      safeBlockVertical = (screenHeight - _safeAreaVertical) / 100;
    } else {
      blockSizeHorizontal = screenWidth / 120;
      blockSizeVertical = screenHeight / 120;

      _safeAreaHorizontal =
          _mediaQueryData.padding.left + _mediaQueryData.padding.right;
      _safeAreaVertical =
          _mediaQueryData.padding.top + _mediaQueryData.padding.bottom;
      safeBlockHorizontal = (screenWidth - _safeAreaHorizontal) / 120;
      safeBlockVertical = (screenHeight - _safeAreaVertical) / 120;
    }
    if (screenWidth > 700) {
      textFactor = 0.8;
    }
  }

  double getWidthRatio(double val) {
    if (screenWidth >= 1200 ||
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return val;
    }
    double res = (val / refWidth) * 100;
    double temp = res * blockSizeHorizontal;
    // print("width$temp");

    return temp;
  }

  double getHeightRatio(double val) {
    if (screenWidth >= 1200 ||
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return val;
    }
    double res = (val / refHeight) * 100;
    double temp = res * blockSizeVertical;
    return temp;
  }

  double getFontRatio(double val) {
    if (screenWidth >= 1200 ||
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return val;
    }
    double res = (val / refWidth) * 100;
    double temp = 0.0;
    if (screenWidth < screenHeight) {
      temp = res * safeBlockHorizontal * textFactor;
    } else {
      temp = res * safeBlockVertical * textFactor;
    }
    // print('$val,$temp,$refHeight,$refWidth');
    return temp;
  }
}

/// A shorthand usage of the functions defined in [SizeConfig].
extension SizeUtils on num {
  double get toWidth => SizeConfig().getWidthRatio(toDouble());

  double get toHeight => SizeConfig().getHeightRatio(toDouble());

  double get toFont => SizeConfig().getFontRatio(toDouble());
}
