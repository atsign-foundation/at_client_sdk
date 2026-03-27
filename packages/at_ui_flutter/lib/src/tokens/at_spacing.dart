import 'dart:ui';

import 'package:flutter/material.dart';

/// Defines the foundational 2-point spacing scale for the Atsign Design System.
class AtSpacing extends ThemeExtension<AtSpacing> {
  final double s2;
  final double s4;
  final double s6;
  final double s8;
  final double s12;
  final double s16;
  final double s20;
  final double s24;
  final double s32;
  final double s36;
  final double s40;
  final double s48;

  const AtSpacing({
    this.s2 = 2.0,
    this.s4 = 4.0,
    this.s6 = 6.0,
    this.s8 = 8.0,
    this.s12 = 12.0,
    this.s16 = 16.0,
    this.s20 = 20.0,
    this.s24 = 24.0,
    this.s32 = 32.0,
    this.s36 = 36.0,
    this.s40 = 40.0,
    this.s48 = 48.0,
  });

  @override
  AtSpacing copyWith({
    double? s2,
    double? s4,
    double? s6,
    double? s8,
    double? s12,
    double? s16,
    double? s20,
    double? s24,
    double? s32,
    double? s36,
    double? s40,
    double? s48,
  }) {
    return AtSpacing(
      s2: s2 ?? this.s2,
      s4: s4 ?? this.s4,
      s6: s6 ?? this.s6,
      s8: s8 ?? this.s8,
      s12: s12 ?? this.s12,
      s16: s16 ?? this.s16,
      s20: s20 ?? this.s20,
      s24: s24 ?? this.s24,
      s32: s32 ?? this.s32,
      s36: s36 ?? this.s36,
      s40: s40 ?? this.s40,
      s48: s48 ?? this.s48,
    );
  }

  @override
  AtSpacing lerp(ThemeExtension<AtSpacing>? other, double t) {
    if (other is! AtSpacing) return this;
    return AtSpacing(
      s2: lerpDouble(s2, other.s2, t) ?? s2,
      s4: lerpDouble(s4, other.s4, t) ?? s4,
      s6: lerpDouble(s6, other.s6, t) ?? s6,
      s8: lerpDouble(s8, other.s8, t) ?? s8,
      s12: lerpDouble(s12, other.s12, t) ?? s12,
      s16: lerpDouble(s16, other.s16, t) ?? s16,
      s20: lerpDouble(s20, other.s20, t) ?? s20,
      s24: lerpDouble(s24, other.s24, t) ?? s24,
      s32: lerpDouble(s32, other.s32, t) ?? s32,
      s36: lerpDouble(s36, other.s36, t) ?? s36,
      s40: lerpDouble(s40, other.s40, t) ?? s40,
      s48: lerpDouble(s48, other.s48, t) ?? s48,
    );
  }

  @override
  int get hashCode {
    return Object.hash(s2, s4, s6, s8, s12, s16, s20, s24, s32, s36, s40, s48);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AtSpacing &&
        other.s2 == s2 &&
        other.s4 == s4 &&
        other.s6 == s6 &&
        other.s8 == s8 &&
        other.s12 == s12 &&
        other.s16 == s16 &&
        other.s20 == s20 &&
        other.s24 == s24 &&
        other.s32 == s32 &&
        other.s36 == s36 &&
        other.s40 == s40 &&
        other.s48 == s48;
  }
}
