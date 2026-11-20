import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:cryptography/cryptography.dart' show Chacha20;
import 'package:test/test.dart';

import 'no_concat_cipher.dart';

/// Catalogue: features/at_chops/chacha20_poly1305_output.feature
void main() {
  test(
      'ChaCha20-Poly1305 encryption with associated data returns the published ciphertext followed by the tag',
      () async {
    // RFC 8439, section 2.8.2. The nonce is that section's 32-bit
    // fixed-common part followed by its 64-bit IV.
    final Uint8List key = _hex(
        '808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
    final Uint8List nonce = _hex('07000000' '4041424344454647');
    final Uint8List plain =
        _hex('4c616469657320616e642047656e746c656d656e206f662074686520636c6173'
            '73206f66202739393a204966204920636f756c64206f6666657220796f75206f'
            '6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73'
            '637265656e20776f756c642062652069742e');
    final Uint8List aad = _hex('50515253c0c1c2c3c4c5c6c7');
    final Uint8List cipherText =
        _hex('d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6'
            '3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36'
            '92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc'
            '3ff4def08e4b7a9de576d26586cec64b6116');
    final Uint8List tag = _hex('1ae10b594f09e26a7e902ecbd0600691');
    final Uint8List expected = Uint8List.fromList([...cipherText, ...tag]);

    final Uint8List out = await const ChaCha20Poly1305Algo()
        .encrypt(plain, key: key, nonce: nonce, aad: aad);

    expect(out, expected,
        reason: "output is not the vector's ciphertext and tag");
  });

  test(
      'ChaCha20-Poly1305 encryption copies the ciphertext and tag into one buffer of exactly their length',
      () async {
    final Uint8List key =
        Uint8List.fromList(List<int>.generate(32, (int i) => i));
    final Uint8List nonce =
        Uint8List.fromList(List<int>.generate(12, (int i) => 0xa0 + i));
    final Uint8List plain =
        Uint8List.fromList(List<int>.generate(1000, (int i) => i & 0xff));

    final Uint8List expected = await const ChaCha20Poly1305Algo()
        .encrypt(plain, key: key, nonce: nonce);
    final Uint8List out = await ChaCha20Poly1305Algo.withCipher(
            NoConcatCipher(Chacha20.poly1305Aead()))
        .encrypt(plain, key: key, nonce: nonce);

    expectExactLengthOutput(out, expected);
  });
}

Uint8List _hex(String s) => Uint8List.fromList(List<int>.generate(s.length ~/ 2,
    (int i) => int.parse(s.substring(2 * i, 2 * i + 2), radix: 16)));
