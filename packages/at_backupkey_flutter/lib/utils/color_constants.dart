import 'package:flutter/material.dart';

class ColorConstants {
  static late bool _isDarkTheme;

  static Color? _highLightColor;

  ///white for darktheme, black for lightTheme.
  static Color primary = Colors.black;

  ///orange shade [Color.fromARGB(255, 240, 94, 62)].
  static const Color buttonHighLightColor = Color.fromARGB(255, 240, 94, 62);

  ///black for darkTheme, white for lightTheme.
  static Color secondary = Colors.white;

  ///shade of grey
  static Color? fillColor = Colors.grey[300];

  static Color? borderColor;

  static const Color redText = Color(0xFFF05E3E);

  ///dark background color
  static Color dark = const Color.fromARGB(255, 45, 42, 48);

  static Color light = Colors.white;

  static Color? backgroundColor;

  static Color? lightBackgroundColor = Colors.grey[600];

  static set setAppColor(Color color) => _highLightColor = color;
  static get appColor => _highLightColor ?? Colors.black;

  static set darkTheme(bool value) {
    _isDarkTheme = value;
    primary = _isDarkTheme ? light : Colors.black;
    secondary = _isDarkTheme ? dark : light;
    backgroundColor = _isDarkTheme ? dark : secondary;
    borderColor = _isDarkTheme ? Colors.grey[700] : Colors.grey[300];
    fillColor = borderColor;
  }
}
