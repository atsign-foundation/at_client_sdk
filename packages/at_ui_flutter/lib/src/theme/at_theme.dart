import 'package:flutter/material.dart';

import '../tokens/at_colors.dart';
import '../tokens/at_elevation.dart';
import '../tokens/at_radius.dart';
import '../tokens/at_spacing.dart';
import '../tokens/at_typography.dart';

/// Centralized theme configurations for the Atsign Design System.
class AtTheme {
  /// The foundational Light Theme for Atsign applications.
  static ThemeData get light {
    final atColors = AtColors.light();
    final atElevation = AtElevation.standard();
    const atRadius = AtRadius();
    const atSpacing = AtSpacing();
    final atTypography = AtTypography.standard();

    return ThemeData.light().copyWith(
      extensions: <ThemeExtension<dynamic>>[
        atColors,
        atElevation,
        atRadius,
        atSpacing,
        atTypography,
      ],

      scaffoldBackgroundColor: atColors.secondary.shade50,
      colorScheme: ColorScheme.light(
        primary: atColors.primary,
        secondary: atColors.secondary,
        surface: atColors.secondary.shade50,
        error: atColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: atColors.secondary.shade900,
        onError: Colors.white,
      ),

      textTheme: TextTheme(
        displayLarge: atTypography.h1,
        displayMedium: atTypography.h2,
        displaySmall: atTypography.h3,
        headlineMedium: atTypography.h4,

        bodyLarge: atTypography.bodyLgRegular,
        bodyMedium: atTypography.bodyMdRegular,
        bodySmall: atTypography.bodySmRegular,
        labelLarge: atTypography.buttonMd,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: atColors.secondary.shade50,
        foregroundColor: atColors.secondary.shade900,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: atTypography.h3.copyWith(
          color: atColors.secondary.shade900,
        ),
      ),
      // 1. ELEVATED BUTTON -> Maps to Atsign "Primary" Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: WidgetStateProperty.all(0), // Spec shows flat buttons
          textStyle: WidgetStateProperty.all(atTypography.buttonMd),
          padding: WidgetStateProperty.all(
            EdgeInsets.symmetric(horizontal: atSpacing.scale16, vertical: 0),
          ),
          minimumSize: WidgetStateProperty.all(
            const Size(0, 40),
          ), // Medium size
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(atRadius.radiusSm),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled))
              return atColors.secondary.shade200;
            if (states.contains(WidgetState.pressed))
              return atColors.primary.shade700;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return atColors.primary.shade600;
            }
            return atColors.primary; // Default 500
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled))
              return atColors.secondary.shade400;
            return Colors.white; // Default text color
          }),
        ),
      ),

      // 2. TEXT BUTTON -> Maps to Atsign "Link" Button
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStateProperty.all(atTypography.buttonMd),
          padding: WidgetStateProperty.all(
            EdgeInsets.symmetric(horizontal: atSpacing.scale12, vertical: 0),
          ),
          minimumSize: WidgetStateProperty.all(const Size(0, 40)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(atRadius.radiusSm),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed))
              return atColors.primary.shade100;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return atColors.primary.shade50;
            }
            return Colors.transparent; // Default
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled))
              return atColors.secondary.shade400;
            if (states.contains(WidgetState.pressed))
              return atColors.primary.shade700;
            if (states.contains(WidgetState.hovered))
              return atColors.primary.shade600;
            return atColors.primary; // Default 500
          }),
        ),
      ),

      // 3. OUTLINED BUTTON -> Standard secondary/outline fallback
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStateProperty.all(atTypography.buttonMd),
          padding: WidgetStateProperty.all(
            EdgeInsets.symmetric(horizontal: atSpacing.scale16, vertical: 0),
          ),
          minimumSize: WidgetStateProperty.all(const Size(0, 40)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(atRadius.sm),
            ),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: atColors.secondary.shade200);
            }
            if (states.contains(WidgetState.pressed)) {
              return BorderSide(color: atColors.secondary.shade400);
            }
            return BorderSide(
              color: atColors.secondary.shade300,
            ); // Default border
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed))
              return atColors.secondary.shade100;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return atColors.secondary.shade50;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled))
              return atColors.secondary.shade400;
            return atColors.secondary.shade900; // Default dark text
          }),
        ),
      ),
    );
  }

  //TODO: Add dark theme support when the design tokens for dark mode are finalized.
}
