import 'dart:convert';

import 'package:at_client_web/src/log_text.dart';
import 'package:at_commons/at_commons.dart' show clipForMessage;
import 'package:test/test.dart';

void main() {
  test('sanitizeLogText escapes control and bidi characters as \\u escapes',
      () {
    expect(sanitizeLogText('a\x01b\u202ec'), r'"a\u0001b\u202ec"');
  });

  test('sanitizeLogText bounds the text with an ellipsis', () {
    expect(sanitizeLogText('x' * 20, maxLength: 10), '"xxxxxxx..."');
  });

  test('singleLine turns every control and bidi character into a space', () {
    expect(singleLine('a\nb\u202ec\x7f'), 'a b c ');
  });

  test('truncateText never splits a surrogate pair', () {
    // Seven units of eight: the cut at four falls between the halves of the
    // emoji (units 3 and 4), so the guard drops its high half.
    const value = 'abc\u{1F600}def';
    final cut = truncateText(value, 7);
    expect(cut, 'abc...');
    expect(cut.codeUnits.where((u) => u & 0xFC00 == 0xD800), isEmpty);
  });

  test(
      'the shared log text sanitizer escapes, bounds and flattens untrusted '
      'text', () {
    // The widened set counts a zero-width space and a supplementary format
    // character as unprintable, as it does controls, bidi formatting and
    // lone surrogates.
    const widened = 'a\x01\u200b\u202eb\u{E0001}';
    expect(sanitizeLogText(widened), r'"a\u0001\u200b\u202eb\udb40\udc01"');
    expect(singleLine(widened), 'a   b ');

    // Eleven units; the bound of ten cuts at seven, between the emoji halves.
    const untrusted = 'a\x01\u202eb\nc\u{1F600}def';
    final quoted = sanitizeLogText(untrusted, maxLength: 10);
    expect(quoted, startsWith('"'));
    expect(quoted, isNot(contains('\n')));
    expect(quoted, contains(r'\u0001'));
    expect(quoted, contains(r'\u202e'));
    expect(quoted, endsWith('c..."'));
    expect(singleLine(untrusted), 'a  b c\u{1F600}def');
    final cut = truncateText(untrusted, 10);
    expect(cut, 'a\x01\u202eb\nc...');
    expect(cut.codeUnits.where((u) => u & 0xFC00 == 0xD800), isEmpty);
  });

  test('the unprintable set matches clipForMessage rune for rune', () {
    // A single rune each, so the two predicates compare directly. Space,
    // backslash and quote are absent: the two functions legitimately differ
    // on them (space is printable, and clipForMessage escapes the other two).
    for (final rune in _parityRunes) {
      final char = String.fromCharCode(rune);
      final label = 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}';
      expect(clipForMessage(char) != char, singleLine(char) == ' ',
          reason: '$label must be unprintable to clipForMessage exactly when '
              'singleLine flattens it');
    }
  });

  test('singleLine preserves a valid surrogate pair', () {
    expect(singleLine('a\u{1F600}b'), 'a\u{1F600}b');
  });

  test('singleLine flattens a lone surrogate to a single space', () {
    expect(singleLine('a${String.fromCharCode(0xD800)}b'), 'a b');
    expect(singleLine('a${String.fromCharCode(0xDFFF)}b'), 'a b');
  });

  test('sanitizeLogText escapes a lone surrogate as a JSON escape', () {
    final value = 'a${String.fromCharCode(0xD800)}b';
    final escaped = sanitizeLogText(value);
    expect(escaped, r'"a\ud800b"');
    expect(jsonDecode(escaped), value);
  });

  test(
      'sanitizeLogText escapes a supplementary format character as a valid '
      'JSON literal', () {
    const value = 'a\u{E0001}b'; // LANGUAGE TAG, a Cf character
    final escaped = sanitizeLogText(value);
    expect(escaped, r'"a\udb40\udc01b"');
    expect(jsonDecode(escaped), value);
  });
}

/// Every boundary of a range in `at_commons`' `clipForMessage`, a sample
/// inside each range, the printable rune just outside every boundary, and a
/// few printable samples.
const _parityRunes = <int>[
  0x00, 0x0a, 0x1f, // controls below 0x20
  0x7e, 0x7f, 0x85, 0x9f, 0xa0, // controls in 0x7f..0x9f
  0xad, 0x61c, 0x6dd, 0x70f, 0x8e2, 0x180e, 0xfeff, // singleton ranges
  0x5ff, 0x600, 0x602, 0x605, 0x606, // 0x0600..0x0605
  0x88f, 0x890, 0x891, 0x892, // 0x0890..0x0891
  0x200a, 0x200b, 0x200d, 0x200f, 0x2010, // 0x200b..0x200f
  0x2027, 0x2028, 0x202c, 0x202e, 0x202f, // 0x2028..0x202e
  0x205f, 0x2060, 0x2066, 0x206f, 0x2070, // 0x2060..0x206f
  0xd7ff, 0xd800, 0xdc00, 0xdfff, 0xe000, // lone surrogates 0xd800..0xdfff
  0xfff8, 0xfff9, 0xfffa, 0xfffb, 0xfffc, // 0xfff9..0xfffb
  0x110bc, 0x110bd, 0x110be, 0x110cc, 0x110cd, 0x110ce, // singletons
  0x1342f, 0x13430, 0x13438, 0x1343f, 0x13440, // 0x13430..0x1343f
  0x1bc9f, 0x1bca0, 0x1bca2, 0x1bca3, 0x1bca4, // 0x1bca0..0x1bca3
  0x1d172, 0x1d173, 0x1d176, 0x1d17a, 0x1d17b, // 0x1d173..0x1d17a
  0xdffff, 0xe0000, 0xe0040, 0xe007f, 0xe0080, // 0xe0000..0xe007f
  0x41, 0x100, 0x1f600, // printable samples
];
