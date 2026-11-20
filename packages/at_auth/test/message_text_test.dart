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
}
