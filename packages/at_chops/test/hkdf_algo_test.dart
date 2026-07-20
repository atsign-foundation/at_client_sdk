import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

/// Hex string → bytes.
Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// bytes → lowercase hex string.
String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('HMAC-SHA256 (RFC 4231 known-answer vectors)', () {
    test('Test Case 1 — "Hi There"', () {
      final key = Uint8List.fromList(List.filled(20, 0x0b));
      final data = hex('4869205468657265'); // "Hi There"
      expect(
        hexOf(HmacSha256.compute(key, data)),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
    });

    test('Test Case 2 — "Jefe"/"what do ya want for nothing?"', () {
      final key = hex('4a656665'); // "Jefe"
      final data =
          hex('7768617420646f2079612077616e7420666f72206e6f7468696e673f');
      expect(
        hexOf(HmacSha256.compute(key, data)),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('different key → different MAC; same inputs → stable', () {
      final data = hex('deadbeef');
      final k1 = Uint8List.fromList(List.filled(32, 1));
      final k2 = Uint8List.fromList(List.filled(32, 2));
      expect(HmacSha256.compute(k1, data), HmacSha256.compute(k1, data));
      expect(HmacSha256.compute(k1, data),
          isNot(equals(HmacSha256.compute(k2, data))));
      expect(HmacSha256.compute(k1, data), hasLength(32));
    });
  });

  group('HKDF-SHA256 (RFC 5869 known-answer vectors)', () {
    test('Test Case 1 — basic, with salt and info', () {
      final ikm = Uint8List.fromList(List.filled(22, 0x0b));
      final salt = hex('000102030405060708090a0b0c');
      final info = hex('f0f1f2f3f4f5f6f7f8f9');
      final okm = HkdfSha256.deriveKey(ikm, salt: salt, info: info, length: 42);
      expect(
        hexOf(okm),
        '3cb25f25faacd57a90434f64d0362f2a'
        '2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });

    test('Test Case 2 — longer inputs and output', () {
      final ikm = Uint8List.fromList(List.generate(80, (i) => i));
      final salt = Uint8List.fromList(List.generate(80, (i) => 0x60 + i));
      final info = Uint8List.fromList(List.generate(80, (i) => 0xb0 + i));
      final okm = HkdfSha256.deriveKey(ikm, salt: salt, info: info, length: 82);
      expect(
        hexOf(okm),
        'b11e398dc80327a1c8e7f78c596a4934'
        '4f012eda2d4efad8a050cc4c19afa97c'
        '59045a99cac7827271cb41c65e590e09'
        'da3275600c2f09b8367793a9aca3db71'
        'cc30c58179ec3e87c14c01d5c1f3434f'
        '1d87',
      );
    });

    test('Test Case 3 — zero-length salt and info', () {
      final ikm = Uint8List.fromList(List.filled(22, 0x0b));
      final okm = HkdfSha256.deriveKey(ikm, length: 42);
      expect(
        hexOf(okm),
        '8da4e775a563c18f715f802a063c5a31'
        'b8a11f5c5ee1879ec3454e5f3c738d2d'
        '9d201395faa4b61a96c8',
      );
    });

    test('deterministic; info binds the output; length-correct', () {
      final ikm = Uint8List.fromList(List.generate(32, (i) => i));
      final salt = Uint8List.fromList('self:@alice:myapp'.codeUnits);
      final c2d = HkdfSha256.deriveKey(ikm,
          salt: salt, info: Uint8List.fromList('c2d'.codeUnits), length: 48);
      final c2dAgain = HkdfSha256.deriveKey(ikm,
          salt: salt, info: Uint8List.fromList('c2d'.codeUnits), length: 48);
      final d2c = HkdfSha256.deriveKey(ikm,
          salt: salt, info: Uint8List.fromList('d2c'.codeUnits), length: 48);
      expect(c2d, hasLength(48));
      expect(c2d, equals(c2dAgain));
      expect(c2d, isNot(equals(d2c)));
    });

    test('rejects out-of-range length', () {
      final ikm = Uint8List.fromList(List.filled(32, 7));
      expect(() => HkdfSha256.deriveKey(ikm, length: 0), throwsArgumentError);
      expect(() => HkdfSha256.deriveKey(ikm, length: 255 * 32 + 1),
          throwsArgumentError);
    });
  });

  group('SHA-256 hashing', () {
    test('SHA256HashingAlgo matches a known digest', () {
      // sha256("abc")
      expect(
        SHA256HashingAlgo().hash('abc'.codeUnits),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });
}
