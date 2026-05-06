/// Stable colour-per-key palette. Used for both per-host (top view) and
/// per-atSign (drill-down) series so each line keeps a consistent
/// colour as new keys appear.
library;

import 'package:flutter/material.dart';

class StableColors {
  static const List<Color> _palette = [
    Color(0xFF1f77b4),
    Color(0xFFff7f0e),
    Color(0xFF2ca02c),
    Color(0xFFd62728),
    Color(0xFF9467bd),
    Color(0xFF8c564b),
    Color(0xFFe377c2),
    Color(0xFF17becf),
    Color(0xFFbcbd22),
    Color(0xFF7f7f7f),
    Color(0xFF005FFF),
    Color(0xFFD7005F),
    Color(0xFF5FAFFF),
    Color(0xFFAFD700),
    Color(0xFFFF00D7),
  ];

  final Map<String, int> _assigned = {};
  int _next = 0;

  Color colorFor(String key) {
    final idx = _assigned.putIfAbsent(key, () {
      final i = _next;
      _next = (_next + 1) % _palette.length;
      return i;
    });
    return _palette[idx];
  }
}
