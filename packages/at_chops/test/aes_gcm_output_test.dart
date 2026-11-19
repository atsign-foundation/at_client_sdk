@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_chops/src/algorithm/ffi/openssl_ffi_bindings.dart'
    show aesGcmEncryptUpdateLength;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:test/test.dart';

/// Catalogue: features/at_chops/aes_gcm_output.feature
void main() {
  test('AES-256-GCM encryption returns the ciphertext followed by the tag',
      () async {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    if (lib == null) fail('libcrypto not available on this host');

    final Uint8List plain = Uint8List.fromList(
        List<int>.generate(1100000 + 7, (int i) => (i * 31 + 7) & 0xff));
    final Uint8List keyBytes =
        Uint8List.fromList(List<int>.generate(32, (int i) => i));
    final Uint8List nonce =
        Uint8List.fromList(List<int>.generate(12, (int i) => 0xa0 + i));
    final AESKey key = AESKey(base64Encode(keyBytes));
    final InitialisationVector iv = InitialisationVector(nonce);

    final Uint8List expected = await _ciphertextThenTag(keyBytes, nonce, plain);

    final AesGcm256FfiAlgo ffi = AesGcm256FfiAlgo.fromLib(lib, key);
    final AesGcm256EncryptionAlgo pure = AesGcm256EncryptionAlgo(key);
    final Uint8List ffiOut = await ffi.encrypt(plain, iv: iv);
    final Uint8List pureOut = await pure.encrypt(plain, iv: iv);

    expect(ffiOut, expected,
        reason: 'FFI output is not the ciphertext followed by the tag');
    expect(pureOut, expected,
        reason: 'pure-Dart output is not the ciphertext followed by the tag');
    expect(await ffi.decrypt(pureOut, iv: iv), plain,
        reason: 'FFI does not decrypt the pure-Dart output');
    expect(await pure.decrypt(ffiOut, iv: iv), plain,
        reason: 'pure-Dart does not decrypt the FFI output');
  });

  test(
      'AES-256-GCM encryption with associated data returns the published ciphertext followed by the tag',
      () async {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    if (lib == null) fail('libcrypto not available on this host');

    // Test Case 16 of McGrew and Viega, "The Galois/Counter Mode of Operation
    // (GCM)", appendix B.
    final AESKey key = AESKey(base64Encode(_hex(
        'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308')));
    final InitialisationVector iv =
        InitialisationVector(_hex('cafebabefacedbaddecaf888'));
    final Uint8List plain =
        _hex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
            '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39');
    final Uint8List aad = _hex('feedfacedeadbeeffeedfacedeadbeefabaddad2');
    final Uint8List cipherText =
        _hex('522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
            '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662');
    final Uint8List tag = _hex('76fc6ece0f4e1768cddf8853bb2d551b');
    final Uint8List expected = Uint8List.fromList([...cipherText, ...tag]);

    final Uint8List ffiOut = await AesGcm256FfiAlgo.fromLib(lib, key)
        .encrypt(plain, iv: iv, aad: aad);
    final Uint8List pureOut =
        await AesGcm256EncryptionAlgo(key).encrypt(plain, iv: iv, aad: aad);

    expect(ffiOut, expected,
        reason: "FFI output is not the vector's ciphertext and tag");
    expect(pureOut, expected,
        reason: "pure-Dart output is not the vector's ciphertext and tag");
  });

  test(
      'AES-256-GCM FFI encryption refuses a reported ciphertext length that differs from the plaintext length',
      () async {
    final DynamicLibrary? lib = tryLoadLibCrypto();
    if (lib == null) fail('libcrypto not available on this host');

    final int Function(int) original = aesGcmEncryptUpdateLength;
    addTearDown(() => aesGcmEncryptUpdateLength = original);
    aesGcmEncryptUpdateLength = (int reported) => reported - 1;

    final AESKey key =
        AESKey(base64Encode(List<int>.generate(32, (int i) => i)));
    final InitialisationVector iv = InitialisationVector(
        Uint8List.fromList(List<int>.generate(12, (int i) => 0xa0 + i)));
    final Uint8List plain =
        Uint8List.fromList(List<int>.generate(60, (int i) => i));

    await expectLater(
        AesGcm256FfiAlgo.fromLib(lib, key).encrypt(plain, iv: iv),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
            'EVP_EncryptUpdate produced a 59-byte ciphertext, expected 60')),
        reason: 'FFI encryption accepted a reported ciphertext length that '
            'differs from the plaintext length');
  });
}

Uint8List _hex(String s) => Uint8List.fromList(List<int>.generate(s.length ~/ 2,
    (int i) => int.parse(s.substring(2 * i, 2 * i + 2), radix: 16)));

/// AES-256-GCM with a 12-byte [nonce] and no associated data, built from
/// AES-256-CTR and GHASH as NIST SP 800-38D defines them.
Future<Uint8List> _ciphertextThenTag(
    Uint8List key, Uint8List nonce, Uint8List plain) async {
  final Uint8List cipherText =
      await _aesCtr(key, _counterBlock(nonce, 2), plain);
  final Uint8List hashKey = await _aesCtr(key, Uint8List(16), Uint8List(16));
  final Uint8List mask =
      await _aesCtr(key, _counterBlock(nonce, 1), Uint8List(16));
  final Uint8List hash = _ghash(hashKey, cipherText);
  final List<int> tag = List<int>.generate(16, (int i) => mask[i] ^ hash[i]);
  return Uint8List.fromList([...cipherText, ...tag]);
}

Uint8List _counterBlock(Uint8List nonce, int counter) => Uint8List(16)
  ..setAll(0, nonce)
  ..buffer.asByteData().setUint32(12, counter);

Future<Uint8List> _aesCtr(
    Uint8List key, Uint8List counterBlock, Uint8List input) async {
  final SecretBox box =
      await DartAesCtr.with256bits(macAlgorithm: MacAlgorithm.empty)
          .encrypt(input, secretKey: SecretKey(key), nonce: counterBlock);
  return Uint8List.fromList(box.cipherText);
}

Uint8List _ghash(Uint8List hashKey, Uint8List cipherText) {
  final ByteData h = ByteData.sublistView(hashKey);
  final int hHi = h.getUint64(0);
  final int hLo = h.getUint64(8);
  int xHi = 0;
  int xLo = 0;
  void absorb(int hi, int lo) {
    (xHi, xLo) = _gfMultiply(xHi ^ hi, xLo ^ lo, hHi, hLo);
  }

  final Uint8List padded = Uint8List((cipherText.length + 15) ~/ 16 * 16)
    ..setAll(0, cipherText);
  final ByteData blocks = ByteData.sublistView(padded);
  for (int i = 0; i < padded.length; i += 16) {
    absorb(blocks.getUint64(i), blocks.getUint64(i + 8));
  }
  absorb(0, cipherText.length * 8);
  return Uint8List(16)
    ..buffer.asByteData().setUint64(0, xHi)
    ..buffer.asByteData().setUint64(8, xLo);
}

(int, int) _gfMultiply(int xHi, int xLo, int yHi, int yLo) {
  int zHi = 0;
  int zLo = 0;
  int vHi = yHi;
  int vLo = yLo;
  for (int i = 0; i < 128; i++) {
    final int bit = i < 64 ? (xHi >>> (63 - i)) & 1 : (xLo >>> (127 - i)) & 1;
    if (bit == 1) {
      zHi ^= vHi;
      zLo ^= vLo;
    }
    final bool carry = (vLo & 1) == 1;
    vLo = (vLo >>> 1) | ((vHi & 1) << 63);
    vHi = vHi >>> 1;
    if (carry) vHi ^= 0xe1 << 56;
  }
  return (zHi, zLo);
}
