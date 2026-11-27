import 'dart:convert';

final _controlChars =
    RegExp(r'[\x00-\x1f\x7f-\x9f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069]');

/// Escapes control and bidirectional formatting characters in [value] as a
/// single-line JSON string literal. [value] is cut to [maxLength] UTF-16 code
/// units (see [truncateText]) before it is encoded, so the quotes and the
/// escapes add to the result's length.
String sanitizeLogText(String value, {int maxLength = 256}) =>
    jsonEncode(truncateText(value, maxLength)).replaceAllMapped(
      _controlChars,
      (m) => '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
    );

/// [value] with every control and bidirectional formatting character
/// replaced by a space, so it stays on one line.
String singleLine(String value) => value.replaceAll(_controlChars, ' ');

/// Whether [value] holds a control or bidirectional formatting character: the
/// same C0, C1 and direction characters [singleLine] flattens, so a
/// notification key that would reorder text on a single line is refused.
bool hasControlText(String value) => _controlChars.hasMatch(value);

/// [value] cut to at most [maxLength] UTF-16 code units, ending in `...`
/// when it was cut, never splitting a surrogate pair.
String truncateText(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  var cut = maxLength > 3 ? maxLength - 3 : maxLength;
  if (cut > 0 &&
      cut < value.length &&
      (value.codeUnitAt(cut - 1) & 0xFC00) == 0xD800) {
    cut--;
  }
  return '${value.substring(0, cut)}...';
}
