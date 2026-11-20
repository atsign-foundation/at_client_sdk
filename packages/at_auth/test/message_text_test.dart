import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_auth/src/passkey/passkey_record.dart'
    show PasskeyRecordCodec;
import 'package:test/test.dart';

class _Sealer implements RecordSealer {
  @override
  Future<Uint8List> seal(Uint8List iv, List<int> plaintext, List<int> aad) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> open(Uint8List iv, Uint8List ciphertext, List<int> aad) =>
      throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  group(
      'Given text from outside the process that holds a line break or another '
      'control, format or line-separator character', () {
    test(
        'when it is clipped for an exception message, then each such '
        'character, and each backslash, is shown as an escape and the message '
        'stays on one line', () async {
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

      await expectLater(
          PasskeyRecordCodec.open(_Sealer(), '@alice', PasskeyRecordType.eid,
              jsonEncode({'v': 'x\ny\u2028"z'})),
          throwsA(isA<UnsupportedPasskeyRecordException>().having(
              (e) => e.message,
              'message',
              allOf(contains(r'unknown version "x\u000ay\u2028\"z"'),
                  isNot(contains('\n')), isNot(contains('\u2028'))))));
      await expectLater(
          PasskeyRecordCodec.open(
              _Sealer(),
              '@alice',
              PasskeyRecordType.eid,
              jsonEncode({
                'v': 2,
                'alg': 'A256GCM',
                'kdf': 'HKDF-SHA256',
                'typ': 'eid',
                'iv': 'x\ny"z',
                'ct': 'AAAA',
              })),
          throwsA(isA<UnsupportedPasskeyRecordException>().having(
              (e) => e.message, 'message', r'not base64: "x\u000ay\"z"')));
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
    const ranges = [
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
    String hex(int rune) => 'U+${rune.toRadixString(16)}';

    test(
        'when the first or last character of a range is clipped, then it is '
        'shown as an escape', () {
      for (final (first, last) in ranges) {
        for (final rune in {first, last}) {
          final escape = rune > 0xffff
              ? '\\u{${rune.toRadixString(16)}}'
              : '\\u${rune.toRadixString(16).padLeft(4, '0')}';
          expect(
              clipForMessage('a${String.fromCharCode(rune)}b'), 'a${escape}b',
              reason: hex(rune));
        }
      }
    });

    test(
        'when the character just before or after a range is clipped, then it '
        'is shown as itself', () {
      for (final (first, last) in ranges) {
        for (final rune in [if (first > 0) first - 1, last + 1]) {
          final text = 'a${String.fromCharCode(rune)}b';
          expect(clipForMessage(text), text, reason: hex(rune));
        }
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
