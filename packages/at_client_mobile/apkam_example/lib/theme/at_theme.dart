import 'package:apkam_example/theme/theme_constants.dart';
import 'package:flutter/material.dart';

class AtTheme extends StatefulWidget {
  const AtTheme({
    required this.child,
    this.themeData,
    super.key,
  });

  final Widget child;
  final ThemeData? themeData;

  @override
  AtThemeState createState() => AtThemeState();
}

class AtThemeState extends State<AtTheme> {
  late Brightness brightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    brightness = Theme.of(context).brightness;
  }

  static final _lightThemeData = ThemeData(
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: kLightBackground,
    colorScheme: ColorScheme.fromSeed(
      brightness: Brightness.light,
      seedColor: kLightPrimary,
      primary: kLightPrimary,
      secondary: kLightSecondary,
      tertiary: kLightTeritary,
      error: kLightError,
      surface: kLightSurface,
      onSurface: kLightOnSurface,
      surfaceContainerHighest: kLightSurfaceVariant,
      onSurfaceVariant: kLightOnSurfaceVariant,
      dynamicSchemeVariant: DynamicSchemeVariant.content,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 24,
          ),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 24,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
        ),
        side: WidgetStateProperty.all(
          const BorderSide(
            color: kLightPrimary,
            width: 2,
          ),
        ),
      ),
    ),
  );

  static final _kDarkThemeData = ThemeData();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: widget.themeData ?? (brightness == Brightness.light ? _lightThemeData : _kDarkThemeData),
      child: Builder(
        builder: (context) {
          return widget.child;
        },
      ),
    );
  }
}
