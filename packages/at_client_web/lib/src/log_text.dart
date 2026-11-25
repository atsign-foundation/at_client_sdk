/// Single-line and JSON-literal forms of untrusted log text.
///
/// The unprintable set mirrors `at_commons`' `clipForMessage` (`_unprintable`):
/// controls (Cc), formats (Cf), line and paragraph separators (Zl, Zp) and
/// lone surrogates, supplementary ranges included. The policies stay local
/// because the shapes differ:
///
/// * [sanitizeLogText] keeps [jsonEncode]'s surrounding quotes, escapes each
///   unprintable rune as a JSON escape (a surrogate pair for a supplementary
///   rune) and bounds the input by inclusive UTF-16 code units
///   ([truncateText]) rather than by characters as written;
/// * [singleLine] flattens unprintable runes to spaces instead of escaping
///   them, for a field a JS caller writes onto one line.
///
/// Follow-up (#2621): share the predicate with `at_commons` once its private
/// `_unprintable` may change, so the two sets cannot drift apart again.
library;

import 'dart:convert';

/// Escapes control, format, separator and lone-surrogate characters in
/// [value] as a single-line JSON string literal. [value] is cut to
/// [maxLength] UTF-16 code units (see [truncateText]) before it is encoded,
/// so the quotes and the escapes add to the result's length; a supplementary
/// character is escaped as a surrogate pair, so the literal stays valid JSON.
String sanitizeLogText(String value, {int maxLength = 256}) {
  final encoded = jsonEncode(truncateText(value, maxLength));
  final out = StringBuffer();
  for (final rune in encoded.runes) {
    out.write(
        _isUnprintable(rune) ? _jsonEscape(rune) : String.fromCharCode(rune));
  }
  return out.toString();
}

/// [value] with every control, format, separator and lone-surrogate character
/// replaced by a space, so it stays on one line.
String singleLine(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    out.write(_isUnprintable(rune) ? ' ' : String.fromCharCode(rune));
  }
  return out.toString();
}

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

/// Whether [rune] is a control (Cc), format (Cf), line or paragraph separator
/// (Zl, Zp) character, or a surrogate.
///
/// Mirrors `at_commons`' `_unprintable` range for range.
bool _isUnprintable(int rune) =>
    rune < 0x20 ||
    (rune >= 0x7f && rune <= 0x9f) ||
    rune == 0xad ||
    (rune >= 0x0600 && rune <= 0x0605) ||
    rune == 0x061c ||
    rune == 0x06dd ||
    rune == 0x070f ||
    (rune >= 0x0890 && rune <= 0x0891) ||
    rune == 0x08e2 ||
    rune == 0x180e ||
    (rune >= 0x200b && rune <= 0x200f) ||
    (rune >= 0x2028 && rune <= 0x202e) ||
    (rune >= 0x2060 && rune <= 0x206f) ||
    (rune >= 0xd800 && rune <= 0xdfff) ||
    rune == 0xfeff ||
    (rune >= 0xfff9 && rune <= 0xfffb) ||
    rune == 0x110bd ||
    rune == 0x110cd ||
    (rune >= 0x13430 && rune <= 0x1343f) ||
    (rune >= 0x1bca0 && rune <= 0x1bca3) ||
    (rune >= 0x1d173 && rune <= 0x1d17a) ||
    (rune >= 0xe0000 && rune <= 0xe007f);

/// [rune] as a JSON escape, a surrogate pair for a supplementary rune so the
/// enclosing string literal stays valid JSON.
String _jsonEscape(int rune) {
  if (rune <= 0xffff) return '\\u${_hex4(rune)}';
  final offset = rune - 0x10000;
  return '\\u${_hex4(0xd800 + (offset >> 10))}'
      '\\u${_hex4(0xdc00 + (offset & 0x3ff))}';
}

String _hex4(int codeUnit) => codeUnit.toRadixString(16).padLeft(4, '0');
