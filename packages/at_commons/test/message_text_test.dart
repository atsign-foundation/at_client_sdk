import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// The escaped ranges `clipForMessage` and the shared predicate both cover.
const _escapedRanges = [
  (0x00, 0x1f),
  (0x7f, 0x9f),
  (0xad, 0xad),
  (0x0600, 0x0605),
  (0x061c, 0x061c),
  (0x06dd, 0x06dd),
  (0x070f, 0x070f),
  (0x0890, 0x0891),
  (0x08e2, 0x08e2),
  (0x180e, 0x180e),
  (0x200b, 0x200f),
  (0x2028, 0x202e),
  (0x2060, 0x206f),
  (0xd800, 0xdfff),
  (0xfeff, 0xfeff),
  (0xfff9, 0xfffb),
  (0x110bd, 0x110bd),
  (0x110cd, 0x110cd),
  (0x13430, 0x1343f),
  (0x1bca0, 0x1bca3),
  (0x1d173, 0x1d17a),
  (0xe0000, 0xe007f),
];
String _hex(int rune) => 'U+${rune.toRadixString(16)}';

void main() {
  group(
      'Given text from outside the process that holds a line break or another '
      'control, format or line-separator character', () {
    test(
        'when it is clipped for an exception message, then each such '
        'character, and each backslash, is shown as an escape and the message '
        'stays on one line', () {
      for (final (text, shown) in [
        ('a\nb', r'a\u000ab'),
        ('a\r\nb', r'a\u000d\u000ab'),
        ('a\tb', r'a\u0009b'),
        ('a\u0000b', r'a\u0000b'),
        ('a\u007fb', r'a\u007fb'),
        ('a\u0085b', r'a\u0085b'),
        ('a\u00adb', r'a\u00adb'),
        ('a\u200bb', r'a\u200bb'),
        ('a\u202eb', r'a\u202eb'),
        ('a\u2028b', r'a\u2028b'),
        ('a\u2029b', r'a\u2029b'),
        ('a\ufeffb', r'a\ufeffb'),
        ('a\u{e0001}b', r'a\u{e0001}b'),
        ('a${String.fromCharCode(0xd800)}b', r'a\ud800b'),
        (r'a\nb', r'a\\nb'),
        ('a"b', 'a"b'),
        ('a\u{1f600}b', 'a\u{1f600}b'),
      ]) {
        expect(clipForMessage(text), shown, reason: jsonEncode(text));
      }
    });

    test(
        'when its escaped form is longer than 180 characters, then the message '
        'carries at most 180 characters of it, never cut inside an escape, '
        'followed by "..."', () {
      final a = 'a' * 174;
      expect(clipForMessage('$a\n'), '$a\\u000a',
          reason: 'an escape that ends at the 180th character is kept whole');
      for (final (text, shown) in [
        ('${'a' * 177}\n${'b' * 10}', '${'a' * 177}...'),
        ('${'a' * 172}\u{e0001}', '${'a' * 172}...'),
        ('${'a' * 179}\\', '${'a' * 179}...'),
        ('${'a' * 179}\u{1f600}', '${'a' * 179}...'),
        ('\n' * 1000, '${r'\u000a' * 30}...'),
      ]) {
        final clipped = clipForMessage(text);
        expect(clipped, shown, reason: jsonEncode(text));
        expect(clipped.length - 3, lessThanOrEqualTo(180));
      }
    });
  });

  group('Given the characters at and beside each end of each escaped range',
      () {
    test(
        'when the first or last character of a range is clipped, then it is '
        'shown as an escape', () {
      for (final (first, last) in _escapedRanges) {
        for (final rune in {first, last}) {
          final escape = rune > 0xffff
              ? '\\u{${rune.toRadixString(16)}}'
              : '\\u${rune.toRadixString(16).padLeft(4, '0')}';
          expect(
              clipForMessage('a${String.fromCharCode(rune)}b'), 'a${escape}b',
              reason: _hex(rune));
        }
      }
    });

    test(
        'when the character just before or after a range is clipped, then it '
        'is shown as itself', () {
      for (final (first, last) in _escapedRanges) {
        for (final rune in [if (first > 0) first - 1, last + 1]) {
          final text = 'a${String.fromCharCode(rune)}b';
          expect(clipForMessage(text), text, reason: _hex(rune));
        }
      }
    });
  });

  group('Given the shared unprintable-rune predicate', () {
    bool covered(int rune) =>
        _escapedRanges.any((range) => rune >= range.$1 && rune <= range.$2);

    test(
        'when it is asked about each end of each range, then it answers '
        'unprintable', () {
      for (final (first, last) in _escapedRanges) {
        for (final rune in {first, last}) {
          expect(isUnprintableRune(rune), isTrue, reason: _hex(rune));
        }
      }
    });

    test(
        'when it is asked about a character just outside a range, then it '
        'answers printable', () {
      for (final (first, last) in _escapedRanges) {
        for (final rune in {if (first > 0) first - 1, last + 1}) {
          if (covered(rune)) continue; // another range covers this neighbour
          expect(isUnprintableRune(rune), isFalse, reason: _hex(rune));
        }
      }
    });

    test(
        'when a printable character is asked about, then it is not '
        'unprintable', () {
      for (final rune in [0x20, 0x41, 0x7e, 0xa0, 0x05d0, 0x1f600]) {
        expect(isUnprintableRune(rune), isFalse, reason: _hex(rune));
      }
    });
  });

  group('Given a quote character', () {
    test('when the text holds it, then each one is shown escaped', () {
      expect(clipForMessage('a"b"', quote: '"'), r'a\"b\"');
      expect(clipForMessage("a'b", quote: "'"), r"a\'b");
      expect(clipForMessage('a"b'), 'a"b',
          reason: 'with no quote given, a quote is shown as it is');
    });

    test(
        'when its escape would cross the clip, then the escape is left out '
        'whole, never cut', () {
      expect(clipForMessage('${'a' * 178}"', quote: '"'), '${'a' * 178}\\"',
          reason: 'an escape that ends at the 180th character is kept whole');
      expect(clipForMessage('${'a' * 179}"b', quote: '"'), '${'a' * 179}...');
      expect(clipForMessage('ab"', maxLength: 3, quote: '"'), 'ab...');
    });

    test(
        'when it is not one printable character other than a backslash, then '
        'clipping throws ArgumentError', () {
      for (final (name, quote) in [
        ('no character', ''),
        ('two characters', '""'),
        ('a line feed', '\n'),
        ('a C1 control character', '\u0085'),
        ('a format character', '\u200b'),
        ('a line separator', '\u2028'),
        ('a paragraph separator', '\u2029'),
        ('a lone surrogate', String.fromCharCode(0xd800)),
        ('a backslash', r'\'),
      ]) {
        expect(() => clipForMessage('a', quote: quote), throwsArgumentError,
            reason: name);
      }
      expect(clipForMessage('a\u{1f600}', quote: '\u{1f600}'), 'a\\\u{1f600}',
          reason: 'one supplementary-plane character is one character');
    });
  });
}
