import 'package:flutter/material.dart';

/// Defines the 50-900 color scale that also acts as a default [Color].
///
/// The base color value passed to the constructor is used as the default [Color].
class AtColorSwatch extends Color {
  final Color shade50;
  final Color shade100;
  final Color shade200;
  final Color shade300;
  final Color shade400;
  final Color shade500;
  final Color shade600;
  final Color shade700;
  final Color shade800;
  final Color shade900;

  const AtColorSwatch(
    /// The base color value for the swatch, which also serves as the default [Color] when the swatch is used directly. This is the same as the 500-weight color in the design system.
    super.primaryShade, {
    required this.shade50,
    required this.shade100,
    required this.shade200,
    required this.shade300,
    required this.shade400,
    required this.shade500,
    required this.shade600,
    required this.shade700,
    required this.shade800,
    required this.shade900,
  });

  /// Allows for smooth animation between two color swatches.
  static AtColorSwatch lerp(AtColorSwatch a, AtColorSwatch b, double t) {
    // we lerp the base color value itself, as well as all the individual shades.
    final Color primaryLerp = Color.lerp(a, b, t) ?? a;

    return AtColorSwatch(
      primaryLerp.toARGB32(),
      shade50: Color.lerp(a.shade50, b.shade50, t) ?? a.shade50,
      shade100: Color.lerp(a.shade100, b.shade100, t) ?? a.shade100,
      shade200: Color.lerp(a.shade200, b.shade200, t) ?? a.shade200,
      shade300: Color.lerp(a.shade300, b.shade300, t) ?? a.shade300,
      shade400: Color.lerp(a.shade400, b.shade400, t) ?? a.shade400,
      shade500: Color.lerp(a.shade500, b.shade500, t) ?? a.shade500,
      shade600: Color.lerp(a.shade600, b.shade600, t) ?? a.shade600,
      shade700: Color.lerp(a.shade700, b.shade700, t) ?? a.shade700,
      shade800: Color.lerp(a.shade800, b.shade800, t) ?? a.shade800,
      shade900: Color.lerp(a.shade900, b.shade900, t) ?? a.shade900,
    );
  }

  @override
  int get hashCode {
    return Object.hash(
      shade50,
      shade100,
      shade200,
      shade300,
      shade400,
      shade500,
      shade600,
      shade700,
      shade800,
      shade900,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AtColorSwatch &&
        other.shade50 == shade50 &&
        other.shade100 == shade100 &&
        other.shade200 == shade200 &&
        other.shade300 == shade300 &&
        other.shade400 == shade400 &&
        other.shade500 == shade500 &&
        other.shade600 == shade600 &&
        other.shade700 == shade700 &&
        other.shade800 == shade800 &&
        other.shade900 == shade900;
  }
}

/// Semantic color tokens for the Atsign Design System,
///
/// These colors align with the design tokens for Primary, Secondary, Success, Info, Warning and Error palettes.
class AtColors extends ThemeExtension<AtColors> {
  final AtColorSwatch primary;
  final AtColorSwatch secondary;
  final AtColorSwatch success;
  final AtColorSwatch info;
  final AtColorSwatch warning;
  final AtColorSwatch error;

  const AtColors({
    required this.primary,
    required this.secondary,
    required this.success,
    required this.info,
    required this.warning,
    required this.error,
  });

  /// Default light theme color palette for the Atsign Design System.
  /// Maps to the 500-weight colors of the design tokens.
  factory AtColors.light() {
    return const AtColors(
      primary: AtColorSwatch(
        0xFFFF6633,
        shade50: Color(0xFFFFF7F4),
        shade100: Color(0xFFFFEDE6),
        shade200: Color(0xFFFFD4C2),
        shade300: Color(0xFFFFB59A),
        shade400: Color(0xFFFF9170),
        shade500: Color(0xFFFF6633),
        shade600: Color(0xFFE5501A),
        shade700: Color(0xFFBF3D0E),
        shade800: Color(0xFF8F2C07),
        shade900: Color(0xFF521704),
      ),
      secondary: AtColorSwatch(
        0xFF8F8F8F,
        shade50: Color(0xFFFCFCFC),
        shade100: Color(0xFFF2F2F2),
        shade200: Color(0xFFE8E8E8),
        shade300: Color(0xFFD4D4D4),
        shade400: Color(0xFFB3B3B3),
        shade500: Color(0xFF8F8F8F),
        shade600: Color(0xFF666666),
        shade700: Color(0xFF444444),
        shade800: Color(0xFF262626),
        shade900: Color(0xFF141414),
      ), // Secondary 500
      success: AtColorSwatch(
        0xFF22C55E,
        shade50: Color(0xFFF0FDF4),
        shade100: Color(0xFFDCFCE7),
        shade200: Color(0xFFBBF7D0),
        shade300: Color(0xFF86EFAC),
        shade400: Color(0xFF4ADE80),
        shade500: Color(0xFF22C55E),
        shade600: Color(0xFF16A34A),
        shade700: Color(0xFF15803D),
        shade800: Color(0xFF166534),
        shade900: Color(0xFF14532D),
      ), // Success 500
      info: AtColorSwatch(
        0xFF3B82F6,
        shade50: Color(0xFFEFF6FF),
        shade100: Color(0xFFDBEAFE),
        shade200: Color(0xFFBFDBFE),
        shade300: Color(0xFF93C5FD),
        shade400: Color(0xFF60A5FA),
        shade500: Color(0xFF3B82F6),
        shade600: Color(0xFF2563EB),
        shade700: Color(0xFF1D4ED8),
        shade800: Color(0xFF1E40AF),
        shade900: Color(0xFF1E3A8A),
      ), // Info 500
      warning: AtColorSwatch(
        0xFFF59E0B,
        shade50: Color(0xFFFFFBEB),
        shade100: Color(0xFFFEF3C7),
        shade200: Color(0xFFFDE68A),
        shade300: Color(0xFFFCD34D),
        shade400: Color(0xFFFBBF24),
        shade500: Color(0xFFF59E0B),
        shade600: Color(0xFFD97706),
        shade700: Color(0xFFB45309),
        shade800: Color(0xFF92400E),
        shade900: Color(0xFF78350F),
      ), // Warning 500
      error: AtColorSwatch(
        0xFFF43F5E,
        shade50: Color(0xFFFFF1F2),
        shade100: Color(0xFFFFE4E6),
        shade200: Color(0xFFFECDD3),
        shade300: Color(0xFFFDA4AF),
        shade400: Color(0xFFFB7185),
        shade500: Color(0xFFF43F5E),
        shade600: Color(0xFFE11D48),
        shade700: Color(0xFFBE123C),
        shade800: Color(0xFF9F1239),
        shade900: Color(0xFF881337),
      ), // Error 500
    );
  }

  @override
  AtColors copyWith({
    AtColorSwatch? primary,
    AtColorSwatch? secondary,
    AtColorSwatch? success,
    AtColorSwatch? info,
    AtColorSwatch? warning,
    AtColorSwatch? error,
  }) {
    return AtColors(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
      info: info ?? this.info,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  AtColors lerp(ThemeExtension<AtColors>? other, double t) {
    if (other is! AtColors) return this;
    return AtColors(
      primary: AtColorSwatch.lerp(primary, other.primary, t),
      secondary: AtColorSwatch.lerp(secondary, other.secondary, t),
      success: AtColorSwatch.lerp(success, other.success, t),
      info: AtColorSwatch.lerp(info, other.info, t),
      warning: AtColorSwatch.lerp(warning, other.warning, t),
      error: AtColorSwatch.lerp(error, other.error, t),
    );
  }

  @override
  int get hashCode {
    return Object.hash(primary, secondary, success, info, warning, error);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AtColors &&
        other.primary == primary &&
        other.secondary == secondary &&
        other.success == success &&
        other.info == info &&
        other.warning == warning &&
        other.error == error;
  }
}
