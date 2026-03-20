import 'dart:ui';

import 'package:flutter/material.dart';

class AtRadius extends ThemeExtension<AtRadius> {
  final double radiusNone;
  final double radiusXs;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusXl;
  final double radius2xl;
  final double radius3xl;
  final double radiusFull;

  const AtRadius({
    this.radiusNone = 0.0,
    this.radiusXs = 4.0,
    this.radiusSm = 6.0,
    this.radiusMd = 8.0,
    this.radiusLg = 10.0,
    this.radiusXl = 12.0,
    this.radius2xl = 16.0,
    this.radius3xl = 20.0,
    this.radiusFull = 999.0,
  });

  @override
  AtRadius copyWith({
    double? radiusNone,
    double? radiusXs,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
    double? radius2xl,
    double? radius3xl,
    double? radiusFull,
  }) {
    return AtRadius(
      radiusNone: radiusNone ?? this.radiusNone,
      radiusXs: radiusXs ?? this.radiusXs,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
      radius2xl: radius2xl ?? this.radius2xl,
      radius3xl: radius3xl ?? this.radius3xl,
      radiusFull: radiusFull ?? this.radiusFull,
    );
  }

  @override
  AtRadius lerp(ThemeExtension<AtRadius>? other, double t) {
    if (other is! AtRadius) return this;
    return AtRadius(
      radiusNone: lerpDouble(radiusNone, other.radiusNone, t) ?? radiusNone,
      radiusXs: lerpDouble(radiusXs, other.radiusXs, t) ?? radiusXs,
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t) ?? radiusSm,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t) ?? radiusMd,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t) ?? radiusLg,
      radiusXl: lerpDouble(radiusXl, other.radiusXl, t) ?? radiusXl,
      radius2xl: lerpDouble(radius2xl, other.radius2xl, t) ?? radius2xl,
      radius3xl: lerpDouble(radius3xl, other.radius3xl, t) ?? radius3xl,
      radiusFull: lerpDouble(radiusFull, other.radiusFull, t) ?? radiusFull,
    );
  }

  @override
  int get hashCode => Object.hash(
    radiusNone,
    radiusXs,
    radiusSm,
    radiusMd,
    radiusLg,
    radiusXl,
    radius2xl,
    radius3xl,
    radiusFull,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AtRadius &&
        other.radiusNone == radiusNone &&
        other.radiusXs == radiusXs &&
        other.radiusSm == radiusSm &&
        other.radiusMd == radiusMd &&
        other.radiusLg == radiusLg &&
        other.radiusXl == radiusXl &&
        other.radius2xl == radius2xl &&
        other.radius3xl == radius3xl &&
        other.radiusFull == radiusFull;
  }
}
