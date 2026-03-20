import 'dart:ui';

import 'package:flutter/material.dart';

/// Defines the foundational 2-point spacing scale for the Atsign Design System.
class AtSpacing extends ThemeExtension<AtSpacing> {
  final double scale2;
  final double scale4;
  final double scale6;
  final double scale8;
  final double scale12;
  final double scale16;
  final double scale20;
  final double scale24;
  final double scale32;
  final double scale36;
  final double scale40;
  final double scale48;

  const AtSpacing({
    this.scale2 = 2.0,
    this.scale4 = 4.0,
    this.scale6 = 6.0,
    this.scale8 = 8.0,
    this.scale12 = 12.0,
    this.scale16 = 16.0,
    this.scale20 = 20.0,
    this.scale24 = 24.0,
    this.scale32 = 32.0,
    this.scale36 = 36.0,
    this.scale40 = 40.0,
    this.scale48 = 48.0,
  });

  @override
  AtSpacing copyWith({
    double? scale2,
    double? scale4,
    double? scale6,
    double? scale8,
    double? scale12,
    double? scale16,
    double? scale20,
    double? scale24,
    double? scale32,
    double? scale36,
    double? scale40,
    double? scale48,
  }) {
    return AtSpacing(
      scale2: scale2 ?? this.scale2,
      scale4: scale4 ?? this.scale4,
      scale6: scale6 ?? this.scale6,
      scale8: scale8 ?? this.scale8,
      scale12: scale12 ?? this.scale12,
      scale16: scale16 ?? this.scale16,
      scale20: scale20 ?? this.scale20,
      scale24: scale24 ?? this.scale24,
      scale32: scale32 ?? this.scale32,
      scale36: scale36 ?? this.scale36,
      scale40: scale40 ?? this.scale40,
      scale48: scale48 ?? this.scale48,
    );
  }

  @override
  AtSpacing lerp(ThemeExtension<AtSpacing>? other, double t) {
    if (other is! AtSpacing) return this;
    return AtSpacing(
      scale2: lerpDouble(scale2, other.scale2, t) ?? scale2,
      scale4: lerpDouble(scale4, other.scale4, t) ?? scale4,
      scale6: lerpDouble(scale6, other.scale6, t) ?? scale6,
      scale8: lerpDouble(scale8, other.scale8, t) ?? scale8,
      scale12: lerpDouble(scale12, other.scale12, t) ?? scale12,
      scale16: lerpDouble(scale16, other.scale16, t) ?? scale16,
      scale20: lerpDouble(scale20, other.scale20, t) ?? scale20,
      scale24: lerpDouble(scale24, other.scale24, t) ?? scale24,
      scale32: lerpDouble(scale32, other.scale32, t) ?? scale32,
      scale36: lerpDouble(scale36, other.scale36, t) ?? scale36,
      scale40: lerpDouble(scale40, other.scale40, t) ?? scale40,
      scale48: lerpDouble(scale48, other.scale48, t) ?? scale48,
    );
  }

  @override
  int get hashCode {
    return Object.hash(
      scale2,
      scale4,
      scale6,
      scale8,
      scale12,
      scale16,
      scale20,
      scale24,
      scale32,
      scale36,
      scale40,
      scale48,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AtSpacing &&
        other.scale2 == scale2 &&
        other.scale4 == scale4 &&
        other.scale6 == scale6 &&
        other.scale8 == scale8 &&
        other.scale12 == scale12 &&
        other.scale16 == scale16 &&
        other.scale20 == scale20 &&
        other.scale24 == scale24 &&
        other.scale32 == scale32 &&
        other.scale36 == scale36 &&
        other.scale40 == scale40 &&
        other.scale48 == scale48;
  }
}
