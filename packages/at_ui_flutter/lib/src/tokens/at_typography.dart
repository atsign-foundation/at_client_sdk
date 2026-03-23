import 'package:flutter/material.dart';

/// Typography tokens for the Atsign Design System.
///
/// Uses 'Poppins' for primary heading and 'Inter' for secondary headings, body and button labels.
class AtTypography extends ThemeExtension<AtTypography> {
  // Headings
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle h4;

  // Body - Large
  final TextStyle bodyLgSemiBold;
  final TextStyle bodyLgMedium;
  final TextStyle bodyLgRegular;

  // Body - Medium
  final TextStyle bodyMdSemiBold;
  final TextStyle bodyMdMedium;
  final TextStyle bodyMdRegular;

  // Body - Small
  final TextStyle bodySmSemiBold;
  final TextStyle bodySmMedium;
  final TextStyle bodySmRegular;

  // Body - Extra Small
  final TextStyle bodyXsSemiBold;
  final TextStyle bodyXsMedium;
  final TextStyle bodyXsRegular;

  // Body - Extra Small
  final TextStyle bodyXxsSemiBold;
  final TextStyle bodyXxsMedium;
  final TextStyle bodyXxsRegular;

  // Buttons
  final TextStyle buttonXl;
  final TextStyle buttonLg;
  final TextStyle buttonMd;
  final TextStyle buttonSm;
  final TextStyle buttonXs;

  const AtTypography({
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.bodyLgSemiBold,
    required this.bodyLgMedium,
    required this.bodyLgRegular,
    required this.bodyMdSemiBold,
    required this.bodyMdMedium,
    required this.bodyMdRegular,
    required this.bodySmSemiBold,
    required this.bodySmMedium,
    required this.bodySmRegular,
    required this.bodyXsSemiBold,
    required this.bodyXsMedium,
    required this.bodyXsRegular,
    required this.bodyXxsSemiBold,
    required this.bodyXxsMedium,
    required this.bodyXxsRegular,
    required this.buttonXl,
    required this.buttonLg,
    required this.buttonMd,
    required this.buttonSm,
    required this.buttonXs,
  });

  /// The default Atsign typography scale.
  factory AtTypography.standard() {
    return AtTypography(
      h1: const TextStyle(
        fontFamily: 'Poppins',
        package: 'at_ui_flutter',
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.0,
        height: 1.1,
      ),
      h2: const TextStyle(
        fontFamily: 'Poppins',
        package: 'at_ui_flutter',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.0,
        height: 1.1,
      ),
      h3: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 24,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        height: 1.1,
      ),
      h4: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        height: 1.1,
      ),
      bodyLgSemiBold: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyLgMedium: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyLgRegular: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 18,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyMdSemiBold: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyMdMedium: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyMdRegular: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodySmSemiBold: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodySmMedium: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodySmRegular: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyXsSemiBold: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyXsMedium: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyXsRegular: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyXxsSemiBold: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyXxsMedium: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      bodyXxsRegular: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 10,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.5,
        height: 1.36,
      ),
      buttonXl: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 20,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.28,
      ),
      buttonLg: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.24,
      ),
      buttonMd: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.24,
      ),
      buttonSm: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.16,
      ),
      buttonXs: const TextStyle(
        fontFamily: 'Inter',
        package: 'at_ui_flutter',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.16,
      ),
    );
  }

  @override
  AtTypography copyWith({
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? h4,
    TextStyle? bodyLgSemiBold,
    TextStyle? bodyLgMedium,
    TextStyle? bodyLgRegular,
    TextStyle? bodyMdSemiBold,
    TextStyle? bodyMdMedium,
    TextStyle? bodyMdRegular,
    TextStyle? bodySmSemiBold,
    TextStyle? bodySmMedium,
    TextStyle? bodySmRegular,
    TextStyle? bodyXsSemiBold,
    TextStyle? bodyXsMedium,
    TextStyle? bodyXsRegular,
    TextStyle? bodyXxsSemiBold,
    TextStyle? bodyXxsMedium,
    TextStyle? bodyXxsRegular,
    TextStyle? buttonXl,
    TextStyle? buttonLg,
    TextStyle? buttonMd,
    TextStyle? buttonSm,
    TextStyle? buttonXs,
  }) {
    return AtTypography(
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      h3: h3 ?? this.h3,
      h4: h4 ?? this.h4,
      bodyLgSemiBold: bodyLgSemiBold ?? this.bodyLgSemiBold,
      bodyLgMedium: bodyLgMedium ?? this.bodyLgMedium,
      bodyLgRegular: bodyLgRegular ?? this.bodyLgRegular,
      bodyMdSemiBold: bodyMdSemiBold ?? this.bodyMdSemiBold,
      bodyMdMedium: bodyMdMedium ?? this.bodyMdMedium,
      bodyMdRegular: bodyMdRegular ?? this.bodyMdRegular,
      bodySmSemiBold: bodySmSemiBold ?? this.bodySmSemiBold,
      bodySmMedium: bodySmMedium ?? this.bodySmMedium,
      bodySmRegular: bodySmRegular ?? this.bodySmRegular,
      bodyXsSemiBold: bodyXsSemiBold ?? this.bodyXsSemiBold,
      bodyXsMedium: bodyXsMedium ?? this.bodyXsMedium,
      bodyXsRegular: bodyXsRegular ?? this.bodyXsRegular,
      bodyXxsSemiBold: bodyXxsSemiBold ?? this.bodyXxsSemiBold,
      bodyXxsMedium: bodyXxsMedium ?? this.bodyXxsMedium,
      bodyXxsRegular: bodyXxsRegular ?? this.bodyXxsRegular,
      buttonXl: buttonXl ?? this.buttonXl,
      buttonLg: buttonLg ?? this.buttonLg,
      buttonMd: buttonMd ?? this.buttonMd,
      buttonSm: buttonSm ?? this.buttonSm,
      buttonXs: buttonXs ?? this.buttonXs,
    );
  }

  @override
  AtTypography lerp(ThemeExtension<AtTypography>? other, double t) {
    if (other is! AtTypography) return this;
    return AtTypography(
      h1: TextStyle.lerp(h1, other.h1, t) ?? h1,
      h2: TextStyle.lerp(h2, other.h2, t) ?? h2,
      h3: TextStyle.lerp(h3, other.h3, t) ?? h3,
      h4: TextStyle.lerp(h4, other.h4, t) ?? h4,
      bodyLgSemiBold:
          TextStyle.lerp(bodyLgSemiBold, other.bodyLgSemiBold, t) ??
          bodyLgSemiBold,
      bodyLgMedium:
          TextStyle.lerp(bodyLgMedium, other.bodyLgMedium, t) ?? bodyLgMedium,
      bodyLgRegular:
          TextStyle.lerp(bodyLgRegular, other.bodyLgRegular, t) ??
          bodyLgRegular,
      bodyMdSemiBold:
          TextStyle.lerp(bodyMdSemiBold, other.bodyMdSemiBold, t) ??
          bodyMdSemiBold,
      bodyMdMedium:
          TextStyle.lerp(bodyMdMedium, other.bodyMdMedium, t) ?? bodyMdMedium,
      bodyMdRegular:
          TextStyle.lerp(bodyMdRegular, other.bodyMdRegular, t) ??
          bodyMdRegular,
      bodySmSemiBold:
          TextStyle.lerp(bodySmSemiBold, other.bodySmSemiBold, t) ??
          bodySmSemiBold,
      bodySmMedium:
          TextStyle.lerp(bodySmMedium, other.bodySmMedium, t) ?? bodySmMedium,
      bodySmRegular:
          TextStyle.lerp(bodySmRegular, other.bodySmRegular, t) ??
          bodySmRegular,
      bodyXsSemiBold:
          TextStyle.lerp(bodyXsSemiBold, other.bodyXsSemiBold, t) ??
          bodyXsSemiBold,
      bodyXsMedium:
          TextStyle.lerp(bodyXsMedium, other.bodyXsMedium, t) ?? bodyXsMedium,
      bodyXsRegular:
          TextStyle.lerp(bodyXsRegular, other.bodyXsRegular, t) ??
          bodyXsRegular,
      bodyXxsSemiBold:
          TextStyle.lerp(bodyXxsSemiBold, other.bodyXxsSemiBold, t) ??
          bodyXxsSemiBold,
      bodyXxsMedium:
          TextStyle.lerp(bodyXxsMedium, other.bodyXxsMedium, t) ??
          bodyXxsMedium,
      bodyXxsRegular:
          TextStyle.lerp(bodyXxsRegular, other.bodyXxsRegular, t) ??
          bodyXxsRegular,
      buttonXl: TextStyle.lerp(buttonXl, other.buttonXl, t) ?? buttonXl,
      buttonLg: TextStyle.lerp(buttonLg, other.buttonLg, t) ?? buttonLg,
      buttonMd: TextStyle.lerp(buttonMd, other.buttonMd, t) ?? buttonMd,
      buttonSm: TextStyle.lerp(buttonSm, other.buttonSm, t) ?? buttonSm,
      buttonXs: TextStyle.lerp(buttonXs, other.buttonXs, t) ?? buttonXs,
    );
  }

  @override
  int get hashCode {
    return Object.hashAll([
      h1,
      h2,
      h3,
      h4,
      bodyLgSemiBold,
      bodyLgMedium,
      bodyLgRegular,
      bodyMdSemiBold,
      bodyMdMedium,
      bodyMdRegular,
      bodySmSemiBold,
      bodySmMedium,
      bodySmRegular,
      bodyXsSemiBold,
      bodyXsMedium,
      bodyXsRegular,
      bodyXxsSemiBold,
      bodyXxsMedium,
      bodyXxsRegular,
      buttonXl,
      buttonLg,
      buttonMd,
      buttonSm,
      buttonXs,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AtTypography &&
        other.h1 == h1 &&
        other.h2 == h2 &&
        other.h3 == h3 &&
        other.h4 == h4 &&
        other.bodyLgSemiBold == bodyLgSemiBold &&
        other.bodyLgMedium == bodyLgMedium &&
        other.bodyLgRegular == bodyLgRegular &&
        other.bodyMdSemiBold == bodyMdSemiBold &&
        other.bodyMdMedium == bodyMdMedium &&
        other.bodyMdRegular == bodyMdRegular &&
        other.bodySmSemiBold == bodySmSemiBold &&
        other.bodySmMedium == bodySmMedium &&
        other.bodySmRegular == bodySmRegular &&
        other.bodyXsSemiBold == bodyXsSemiBold &&
        other.bodyXsMedium == bodyXsMedium &&
        other.bodyXsRegular == bodyXsRegular &&
        other.bodyXxsSemiBold == bodyXxsSemiBold &&
        other.bodyXxsMedium == bodyXxsMedium &&
        other.bodyXxsRegular == bodyXxsRegular &&
        other.buttonXl == buttonXl &&
        other.buttonLg == buttonLg &&
        other.buttonMd == buttonMd &&
        other.buttonSm == buttonSm &&
        other.buttonXs == buttonXs;
  }
}
