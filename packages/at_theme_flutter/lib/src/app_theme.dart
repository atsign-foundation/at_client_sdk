import 'dart:convert';

import 'package:at_utils/at_utils.dart';
import 'package:flutter/material.dart';

import 'color_constants.dart';
import 'inherited_app_theme.dart';

class AppTheme {
  /// The overall brightness of this color scheme.
  final Brightness brightness;

  /// The color displayed most frequently across your app’s screens and components.
  final Color primaryColor;

  /// An accent color that, when used sparingly, calls attention to parts
  /// of your app.
  final Color secondaryColor;

  Color get accentColor => secondaryColor;

  /// A color that typically appears behind scrollable content.
  final Color backgroundColor;

  static final AtSignLogger _logger = AtSignLogger('AppTheme');

  /// Create a ColorScheme instance.
  AppTheme({
    required this.brightness,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
  });

  factory AppTheme.from({
    Brightness brightness = Brightness.light,
    Color primaryColor = ColorConstants.primaryDefault,
    Color? secondaryColor,
    Color? backgroundColor,
  }) {
    return AppTheme(
      primaryColor: primaryColor,
      secondaryColor: secondaryColor ?? ColorConstants.secondary,
      backgroundColor: backgroundColor ??
          (brightness == Brightness.dark ? ColorConstants.backgroundDark : ColorConstants.backgroundLight),
      brightness: brightness,
    );
  }

  AppTheme copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    Color? backgroundColor,
    Brightness? brightness,
  }) {
    return AppTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      brightness: brightness ?? this.brightness,
    );
  }

  ThemeData toThemeData() {
    return ThemeData(
      brightness: brightness,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(color: primaryColor),
      colorScheme:
          ThemeData().colorScheme.copyWith(secondary: accentColor, brightness: brightness, surface: backgroundColor),
    );
  }

  static AppTheme of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<InheritedAppTheme>()!.theme;
  }

  encoded() {
    var appTheme = {
      'brightness': brightness.toString(),
      'primaryColor': primaryColor.toARGB32().toString(),
      'secondaryColor': secondaryColor.toARGB32().toString(),
      'backgroundColor': backgroundColor.toARGB32().toString()
    };

    return jsonEncode(appTheme);
  }

  static decode(Map<String, dynamic> jsonMap) {
    try {
      return AppTheme(
        brightness: jsonMap['brightness'] == 'Brightness.dark' ? Brightness.dark : Brightness.light,
        primaryColor:
            jsonMap['primaryColor'] != null ? Color(int.parse(jsonMap['primaryColor'])) : const Color(0xFF6EBCB7),
        secondaryColor:
            jsonMap['secondaryColor'] != null ? Color(int.parse(jsonMap['secondaryColor'])) : const Color(0xFF6EBCB7),
        backgroundColor:
            jsonMap['backgroundColor'] != null ? Color(int.parse(jsonMap['backgroundColor'])) : Colors.white,
      );
    } catch (e) {
      _logger.severe('error in decode theme data: ${e.toString()}');
      return AppTheme.from(secondaryColor: ColorConstants.secondary, backgroundColor: ColorConstants.backgroundDark);
    }
  }
}
