import 'dart:ui';

import 'package:flutter/material.dart';

class AtRadius extends ThemeExtension<AtRadius> {
  final double none;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double x2l;
  final double x3l;
  final double full;

  const AtRadius({
    this.none = 0.0,
    this.xs = 4.0,
    this.sm = 6.0,
    this.md = 8.0,
    this.lg = 10.0,
    this.xl = 12.0,
    this.x2l = 16.0,
    this.x3l = 20.0,
    this.full = 999.0,
  });

  @override
  AtRadius copyWith({
    double? none,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? x2l,
    double? x3l,
    double? full,
  }) {
    return AtRadius(
      none: none ?? this.none,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      x2l: x2l ?? this.x2l,
      x3l: x3l ?? this.x3l,
      full: full ?? this.full,
    );
  }

  @override
  AtRadius lerp(ThemeExtension<AtRadius>? other, double t) {
    if (other is! AtRadius) return this;
    return AtRadius(
      none: lerpDouble(none, other.none, t) ?? none,
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
      x2l: lerpDouble(x2l, other.x2l, t) ?? x2l,
      x3l: lerpDouble(x3l, other.x3l, t) ?? x3l,
      full: lerpDouble(full, other.full, t) ?? full,
    );
  }

  @override
  int get hashCode => Object.hash(none, xs, sm, md, lg, xl, x2l, x3l, full);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AtRadius &&
        other.none == none &&
        other.xs == xs &&
        other.sm == sm &&
        other.md == md &&
        other.lg == lg &&
        other.xl == xl &&
        other.x2l == x2l &&
        other.x3l == x3l &&
        other.full == full;
  }
}
