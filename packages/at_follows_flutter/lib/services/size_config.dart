import 'package:flutter/material.dart';

class SizeConfig {
  SizeConfig._();

  static SizeConfig _instance = SizeConfig._();

  factory SizeConfig() => _instance;
  late MediaQueryData _mediaQueryData;
  double? screenWidth;
  late double screenHeight;
  late double blockSizeHorizontal;
  late double blockSizeVertical;
  double? deviceTextFactor;

  late double _safeAreaHorizontal;
  late double _safeAreaVertical;
  late double safeBlockHorizontal;
  late double safeBlockVertical;

  double? profileDrawerWidth;
  late double refHeight;
  late double refWidth;

  void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    refHeight = 812;
    refWidth = 375;

    deviceTextFactor = _mediaQueryData.textScaler.scale(20) / 20;

    // print("height is::: $screenHeight");

    if (screenHeight < 1200) {
      blockSizeHorizontal = screenWidth! / 100;
      blockSizeVertical = screenHeight / 100;

      _safeAreaHorizontal =
          _mediaQueryData.padding.left + _mediaQueryData.padding.right;
      _safeAreaVertical =
          _mediaQueryData.padding.top + _mediaQueryData.padding.bottom;
      safeBlockHorizontal = (screenWidth! - _safeAreaHorizontal) / 100;
      safeBlockVertical = (screenHeight - _safeAreaVertical) / 100;
    } else {
      blockSizeHorizontal = screenWidth! / 120;
      blockSizeVertical = screenHeight / 120;

      _safeAreaHorizontal =
          _mediaQueryData.padding.left + _mediaQueryData.padding.right;
      _safeAreaVertical =
          _mediaQueryData.padding.top + _mediaQueryData.padding.bottom;
      safeBlockHorizontal = (screenWidth! - _safeAreaHorizontal) / 120;
      safeBlockVertical = (screenHeight - _safeAreaVertical) / 120;
    }
  }

  double getWidthRatio(double val) {
    double res = (val / refWidth) * 100;
    double temp = res * blockSizeHorizontal;
    // print("width$temp");

    return temp;
  }

  double getHeightRatio(double val) {
    double res = (val / refHeight) * 100;
    double temp = res * blockSizeVertical;
    return temp;
  }

  double getFontRatio(double val) {
    double res = (val / refWidth) * 100;
    double temp = 0.0;
    if (screenWidth! < screenHeight) {
      temp = res * safeBlockHorizontal;
    } else {
      temp = res * safeBlockVertical;
    }
    // print('$val,$temp,$refHeight,$refWidth');
    return temp;
  }
}

extension SizeUtils on num {
  ///makes the [width] responsive on different screen sizes
  double get toWidth => SizeConfig().getWidthRatio(this.toDouble());

  ///makes the [height] responsive on different screen sizes
  double get toHeight => SizeConfig().getHeightRatio(this.toDouble());

  ///makes the [font] responsive on different screen sizes
  double get toFont => SizeConfig().getFontRatio(this.toDouble());
}
