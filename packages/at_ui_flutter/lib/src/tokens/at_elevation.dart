import 'package:flutter/material.dart';

/// Elevation tokens for the Atsign Design System.
///
/// Provides predefined [BoxShadow] lists to ensue consistent depth, layering, and visual hierarchy across the application.
class AtElevation extends ThemeExtension<AtElevation> {
  final List<BoxShadow> neutral0;
  final List<BoxShadow> neutral1;
  final List<BoxShadow> neutral2;
  final List<BoxShadow> neutral3;
  final List<BoxShadow> neutral4;
  final List<BoxShadow> neutral5;

  // Semantic (orange) Elevations
  final List<BoxShadow> semantic0;
  final List<BoxShadow> semantic1;
  final List<BoxShadow> semantic2;
  final List<BoxShadow> semantic3;
  final List<BoxShadow> semantic4;
  final List<BoxShadow> semantic5;

  const AtElevation({
    required this.neutral0,
    required this.neutral1,
    required this.neutral2,
    required this.neutral3,
    required this.neutral4,
    required this.neutral5,
    required this.semantic0,
    required this.semantic1,
    required this.semantic2,
    required this.semantic3,
    required this.semantic4,
    required this.semantic5,
  });

  /// THe default Atsign Elevation scale.
  factory AtElevation.standard() {
    return const AtElevation(
      // --- Neutral ---
      neutral0: [], // No shadow
      neutral1: [
        BoxShadow(
          color: Color(0x0C000000),
          offset: Offset(0, 2),
          blurRadius: 5,
        ),
      ],
      neutral2: [
        BoxShadow(
          color: Color(0x11000000),
          offset: Offset(0, 4),
          blurRadius: 12,
        ),
      ],
      neutral3: [
        BoxShadow(
          color: Color(0x19000000),
          offset: Offset(0, 6),
          blurRadius: 16,
        ),
        BoxShadow(
          color: Color(0xB2FFFFFF),
          offset: Offset(0, -1),
          blurRadius: 4,
        ),
      ],
      neutral4: [
        BoxShadow(
          color: Color(0x1E000000),
          offset: Offset(0, 10),
          blurRadius: 28,
        ),
        BoxShadow(
          color: Color(0xCCFFFFFF),
          offset: Offset(0, -2),
          blurRadius: 6,
        ),
      ],
      neutral5: [
        BoxShadow(
          color: Color(0x26000000),
          offset: Offset(0, 16),
          blurRadius: 40,
        ),
        BoxShadow(
          color: Color(0xE5FFFFFF),
          offset: Offset(0, -2),
          blurRadius: 8,
        ),
      ],

      // --- Semantic ---
      semantic0: [], // No shadow
      semantic1: [
        BoxShadow(
          color: Color(0x14FF6B4A),
          offset: Offset(0, 2),
          blurRadius: 6,
        ),
      ],
      semantic2: [
        BoxShadow(
          color: Color(0x1EFF6B4A),
          offset: Offset(0, 4),
          blurRadius: 12,
        ),
      ],
      semantic3: [
        BoxShadow(
          color: Color(0x2DFF6B4A),
          offset: Offset(0, 6),
          blurRadius: 16,
        ),
        BoxShadow(
          color: Color(0xB2FFFFFF),
          offset: Offset(0, -1),
          blurRadius: 4,
        ),
      ],
      semantic4: [
        BoxShadow(
          color: Color(0x3FFF6B4A),
          offset: Offset(0, 10),
          blurRadius: 28,
        ),
        BoxShadow(
          color: Color(0xCCFFFFFF),
          offset: Offset(0, -2),
          blurRadius: 6,
        ),
      ],
      semantic5: [
        BoxShadow(
          color: Color(0x51FF6B4A),
          offset: Offset(0, 16),
          blurRadius: 40,
        ),
        BoxShadow(
          color: Color(0xE5FFFFFF),
          offset: Offset(0, -2),
          blurRadius: 8,
        ),
      ],
    );
  }

  @override
  AtElevation copyWith({
    List<BoxShadow>? neutral0,
    List<BoxShadow>? neutral1,
    List<BoxShadow>? neutral2,
    List<BoxShadow>? neutral3,
    List<BoxShadow>? neutral4,
    List<BoxShadow>? neutral5,
    List<BoxShadow>? semantic0,
    List<BoxShadow>? semantic1,
    List<BoxShadow>? semantic2,
    List<BoxShadow>? semantic3,
    List<BoxShadow>? semantic4,
    List<BoxShadow>? semantic5,
  }) {
    return AtElevation(
      neutral0: neutral0 ?? this.neutral0,
      neutral1: neutral1 ?? this.neutral1,
      neutral2: neutral2 ?? this.neutral2,
      neutral3: neutral3 ?? this.neutral3,
      neutral4: neutral4 ?? this.neutral4,
      neutral5: neutral5 ?? this.neutral5,
      semantic0: semantic0 ?? this.semantic0,
      semantic1: semantic1 ?? this.semantic1,
      semantic2: semantic2 ?? this.semantic2,
      semantic3: semantic3 ?? this.semantic3,
      semantic4: semantic4 ?? this.semantic4,
      semantic5: semantic5 ?? this.semantic5,
    );
  }

  @override
  AtElevation lerp(ThemeExtension<AtElevation>? other, double t) {
    if (other is! AtElevation) return this;
    return AtElevation(
      neutral0: BoxShadow.lerpList(neutral0, other.neutral0, t) ?? neutral0,
      neutral1: BoxShadow.lerpList(neutral1, other.neutral1, t) ?? neutral1,
      neutral2: BoxShadow.lerpList(neutral2, other.neutral2, t) ?? neutral2,
      neutral3: BoxShadow.lerpList(neutral3, other.neutral3, t) ?? neutral3,
      neutral4: BoxShadow.lerpList(neutral4, other.neutral4, t) ?? neutral4,
      neutral5: BoxShadow.lerpList(neutral5, other.neutral5, t) ?? neutral5,
      semantic0: BoxShadow.lerpList(semantic0, other.semantic0, t) ?? semantic0,
      semantic1: BoxShadow.lerpList(semantic1, other.semantic1, t) ?? semantic1,
      semantic2: BoxShadow.lerpList(semantic2, other.semantic2, t) ?? semantic2,
      semantic3: BoxShadow.lerpList(semantic3, other.semantic3, t) ?? semantic3,
      semantic4: BoxShadow.lerpList(semantic4, other.semantic4, t) ?? semantic4,
      semantic5: BoxShadow.lerpList(semantic5, other.semantic5, t) ?? semantic5,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AtElevation &&
        other.neutral0 == neutral0 &&
        other.neutral1 == neutral1 &&
        other.neutral2 == neutral2 &&
        other.neutral3 == neutral3 &&
        other.neutral4 == neutral4 &&
        other.neutral5 == neutral5 &&
        other.semantic0 == semantic0 &&
        other.semantic1 == semantic1 &&
        other.semantic2 == semantic2 &&
        other.semantic3 == semantic3 &&
        other.semantic4 == semantic4 &&
        other.semantic5 == semantic5;
  }

  @override
  int get hashCode {
    return Object.hash(
      neutral0,
      neutral1,
      neutral2,
      neutral3,
      neutral4,
      neutral5,
      semantic0,
      semantic1,
      semantic2,
      semantic3,
      semantic4,
      semantic5,
    );
  }
}
