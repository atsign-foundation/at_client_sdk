/// A thrown diagnostic must carry the value it names. An escaped `\$` in a
/// message string compiles cleanly and reads plausibly in review, but the
/// message then contains the interpolation's source text instead of the value
/// — and the one person who ever sees it is mid-failure, being told nothing.
library;

import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  final sharedSecret = Uint8List(32);

  Matcher throwsArgumentErrorNaming(String value) =>
      throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains(value), isNot(contains(r'${')))));

  test('an unknown pqSeal version is named in hex in the diagnostic', () {
    expect(() => pqSealDeriveKeyAndNonce(sharedSecret, version: 0x7f),
        throwsArgumentErrorNaming('0x7f'));
  });

  test('an unknown HPKE KDF id is named in hex by labeledExtract', () {
    const bogusKdf = HpkeSuite(
        kemId: 0x647A, kdfId: 0x9999, aeadId: 0x0003, nk: 32, nn: 12, nh: 32);
    expect(
        () => labeledExtract(
            bogusKdf, Uint8List(0), 'psk_id_hash', Uint8List(0)),
        throwsArgumentErrorNaming('0x9999'));
  });

  test('an unknown HPKE KDF id is named in hex by labeledExpand', () {
    const bogusKdf = HpkeSuite(
        kemId: 0x647A, kdfId: 0x9999, aeadId: 0x0003, nk: 32, nn: 12, nh: 32);
    expect(
        () => labeledExpand(
            bogusKdf, Uint8List(32), 'key', Uint8List(0), 32),
        throwsArgumentErrorNaming('0x9999'));
  });
}
