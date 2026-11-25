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
    // Every code point, not a hand-picked boundary list, so a range added to
    // either predicate cannot slip past it. Four code points are excluded as
    // the known differences between the two policies: space (a printable that
    // singleLine also renders as a space), backslash (clipForMessage escapes
    // it), quote (clipForMessage escapes it when given as the quote argument)
    // and newline (clipForMessage escapes it rather than flattening it).
    const known = {0x20, 0x22, 0x5c, 0x0a};
    var swept = 0;
    for (var rune = 0; rune <= 0x10ffff; rune++) {
      if (known.contains(rune)) continue;
      swept++;
      final char = String.fromCharCode(rune);
      final escapedByClip = clipForMessage(char) != char;
      final flattened = singleLine(char) == ' ';
      if (escapedByClip != flattened) {
        final label =
            'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        fail('$label must be unprintable to clipForMessage exactly when '
            'singleLine flattens it');
      }
    }
    expect(swept, 0x110000 - known.length);
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
