import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

/// SHA-256 of `atsign:keys:lookup:v1`; changing it re-keys every passkey.
final _pinnedPrfSalt = Uint8List.fromList(const [
  0xe5,
  0x83,
  0x0b,
  0x40,
  0x9d,
  0xb0,
  0xe5,
  0x03,
  0xaf,
  0x40,
  0xc2,
  0x54,
  0x59,
  0x8c,
  0x41,
  0xbf,
  0x4e,
  0x6a,
  0xd6,
  0x62,
  0x7f,
  0xf1,
  0x85,
  0xd3,
  0x11,
  0xa9,
  0xf4,
  0x46,
  0x38,
  0x3e,
  0xa6,
  0x20,
]);

void main() {
  String hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  group('recordPrfSalt', () {
    test('the PRF eval input is the pinned literal', () {
      expect(recordPrfSalt(), _pinnedPrfSalt);
    });

    test('is SHA-256 of atsign:keys:lookup:v1', () {
      expect(hex(recordPrfSalt()),
          'e5830b409db0e503af40c254598c41bf4e6ad6627ff185d311a9f446383ea620');
    });
  });
}
