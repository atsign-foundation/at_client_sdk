import 'package:at_commons/at_commons.dart';
import 'package:flutter/material.dart';

import '../services/atsign_colors.dart';

/// A coloured rendering of an atSign — bold orange for self, stable
/// palette-assigned colour for everyone else.
class AtsignText extends StatelessWidget {
  final Atsign atSign;
  final AtsignColors colors;
  final TextStyle? style;

  const AtsignText({
    super.key,
    required this.atSign,
    required this.colors,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Text(atSign.toString(), style: colors.styleFor(atSign, base: style));
  }
}

/// Renders a set of atSigns as a comma-separated coloured list.
class AtsignList extends StatelessWidget {
  final Iterable<Atsign> atSigns;
  final AtsignColors colors;
  final TextStyle? style;
  final String emptyLabel;

  const AtsignList({
    super.key,
    required this.atSigns,
    required this.colors,
    this.style,
    this.emptyLabel = '(none)',
  });

  @override
  Widget build(BuildContext context) {
    if (atSigns.isEmpty) {
      return Text(emptyLabel, style: style);
    }
    final list = atSigns.toList();
    final spans = <InlineSpan>[];
    for (int i = 0; i < list.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ', '));
      spans.add(
        TextSpan(
          text: list[i].toString(),
          style: colors.styleFor(list[i], base: style),
        ),
      );
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}
