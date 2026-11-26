import 'dart:convert';

import 'package:at_client_web/src/log_text.dart';
import 'package:test/test.dart';

/// U+202E RIGHT-TO-LEFT OVERRIDE.
String _bidi() => String.fromCharCode(0x202e);

/// U+200B ZERO WIDTH SPACE.
String _zeroWidth() => String.fromCharCode(0x200b);

/// U+E0001 LANGUAGE TAG, a supplementary format character.
String _languageTag() => String.fromCharCode(0xe0001);

/// U+1F600 GRINNING FACE, a printable supplementary character.
String _emoji() => String.fromCharCode(0x1f600);

void main() {
  test('sanitizeLogText escapes control and bidi characters as \\u escapes',
      () {
    expect(sanitizeLogText('a\x01b${_bidi()}c'), r'"a\u0001b\u202ec"');
  });

  test('sanitizeLogText bounds the text with an ellipsis', () {
    expect(sanitizeLogText('x' * 20, maxLength: 10), '"xxxxxxx..."');
  });

  test('singleLine turns every control and bidi character into a space', () {
    expect(singleLine('a\nb${_bidi()}c\x7f'), 'a b c ');
  });

  test('truncateText never splits a surrogate pair', () {
    // Seven units of eight: the cut at four falls between the halves of the
    // emoji (units 3 and 4), so the guard drops its high half.
    final value = 'abc${_emoji()}def';
    final cut = truncateText(value, 7);
    expect(cut, 'abc...');
    expect(cut.codeUnits.where((u) => u & 0xFC00 == 0xD800), isEmpty);
  });

  test(
      'the local log text sanitizer escapes, bounds and flattens untrusted '
      'text', () {
    // The widened set counts a zero-width space and a supplementary format
    // character as unprintable, as it does controls, bidi formatting and
    // lone surrogates. A supplementary rune is escaped as a surrogate pair,
    // so the literal stays valid JSON.
    final widened = 'a\x01${_zeroWidth()}${_bidi()}b${_languageTag()}';
    expect(sanitizeLogText(widened), r'"a\u0001\u200b\u202eb\udb40\udc01"');
    expect(singleLine(widened), 'a   b ');

    // Eleven units; the bound of ten cuts at seven, between the emoji halves.
    final untrusted = 'a\x01${_bidi()}b\nc${_emoji()}def';
    final quoted = sanitizeLogText(untrusted, maxLength: 10);
    expect(quoted, startsWith('"'));
    expect(quoted, isNot(contains('\n')));
    expect(quoted, contains(r'\u0001'));
    expect(quoted, contains(r'\u202e'));
    expect(quoted, endsWith('c..."'));
    expect(singleLine(untrusted), 'a  b c${_emoji()}def');
    final cut = truncateText(untrusted, 10);
    expect(cut, 'a\x01${_bidi()}b\nc...');
    expect(cut.codeUnits.where((u) => u & 0xFC00 == 0xD800), isEmpty);
  });

  test('singleLine preserves a valid surrogate pair', () {
    expect(singleLine('a${_emoji()}b'), 'a${_emoji()}b');
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

  test('sanitizeLogText keeps a printable supplementary rune as it is', () {
    final value = 'a${_emoji()}b';
    expect(sanitizeLogText(value), '"a${_emoji()}b"');
    expect(jsonDecode(sanitizeLogText(value)), value);
  });

  test(
      'sanitizeLogText escapes a supplementary format character as a valid '
      'JSON literal', () {
    final value = 'a${_languageTag()}b';
    final escaped = sanitizeLogText(value);
    expect(escaped, r'"a\udb40\udc01b"');
    expect(jsonDecode(escaped), value);
  });
}
