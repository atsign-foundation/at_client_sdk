import 'package:flutter/material.dart';

class ColorConstants {
  static late bool _isDarkTheme;

  ///white for darktheme, black for lightTheme.
  static Color? primary;

  ///orange shade [Color.fromARGB(255, 240, 94, 62)].
  static Color? buttonHighLightColor;

  ///black for darkTheme, white for lightTheme.
  static Color? secondary;

  ///shade of grey
  // static Color borderLightColor = Colors.grey[300];
  static Color? fillColor = Colors.grey[300];

  static Color? borderColor;

  ///dark background color
  static Color dark = Color.fromARGB(255, 45, 42, 48);

  static Color light = Colors.white;

  static Color? activeColor;
  static Color? inactiveThumbColor = fillColor;
  static Color? inactiveTrackColor = Colors.grey[200];
  static Color? activeTrackColor;
  static Brightness? brightness;
  static Color? backgroundColor;
  static set appColor(Color? color) {
    buttonHighLightColor = color ?? Color.fromARGB(255, 240, 94, 62);
    activeColor = buttonHighLightColor;
    activeTrackColor = buttonHighLightColor!.withOpacity(0.2);
  }

  // static Color _lightBackgroundColor = Colors.grey[400];
  // static Color _darkBackgroundColor = Color.fromARGB(255, 45, 42, 48);

  static set darkTheme(bool value) {
    _isDarkTheme = value;
    primary = _isDarkTheme ? light : Colors.black;
    secondary = _isDarkTheme ? dark : light;
    backgroundColor = _isDarkTheme ? dark : secondary;
    borderColor = _isDarkTheme ? Colors.grey[700] : Colors.grey[300];
    fillColor = borderColor;
    brightness = _isDarkTheme ? Brightness.dark : Brightness.light;
  }
}
