import 'package:at_commons/at_commons.dart';
import 'package:flutter/material.dart';

/// Assigns a stable, visually distinct colour to each atSign encountered.
/// Self (the current user) is always rendered in bold orange to match the TUI.
class AtsignColors {
  // RGB approximations of the ANSI-256 codes the TUI uses.
  static const List<Color> _palette = [
    Color(0xFF005FFF), // 27
    Color(0xFF0087FF), // 33
    Color(0xFF00AFFF), // 39
    Color(0xFF5F5FFF), // 63
    Color(0xFF5F87FF), // 69
    Color(0xFF5FAFFF), // 75
    Color(0xFF5FD700), // 76
    Color(0xFF5FFF00), // 82
    Color(0xFF875FFF), // 99
    Color(0xFF8787FF), // 105
    Color(0xFFAF00FF), // 129
    Color(0xFFAF5FFF), // 135
    Color(0xFFAF87FF), // 141
    Color(0xFFAFD700), // 148
    Color(0xFFD70000), // 160
    Color(0xFFD7005F), // 161
    Color(0xFFD70087), // 162
    Color(0xFFD75F00), // 166
    Color(0xFFD78700), // 172
    Color(0xFFD7AF00), // 178
    Color(0xFFFF0000), // 196
    Color(0xFFFF00D7), // 200
    Color(0xFFFF00FF), // 201
    Color(0xFFFF5F00), // 202
    Color(0xFFFF8700), // 208 — reserved for self as a distinct bold orange
    Color(0xFFFFAF00), // 214
  ];

  static const Color selfColor = Color(0xFFFF8700);

  final Atsign self;
  final Map<String, int> _assigned = {};
  int _nextIdx = 0;

  AtsignColors(this.self);

  Color colorFor(Atsign a) {
    if (a == self) return selfColor;
    final key = a.toString();
    final idx = _assigned.putIfAbsent(key, () {
      final i = _nextIdx;
      _nextIdx = (_nextIdx + 1) % _palette.length;
      return i;
    });
    return _palette[idx];
  }

  TextStyle styleFor(Atsign a, {TextStyle? base}) {
    final b = base ?? const TextStyle();
    if (a == self) {
      return b.copyWith(color: selfColor, fontWeight: FontWeight.bold);
    }
    return b.copyWith(color: colorFor(a));
  }
}
