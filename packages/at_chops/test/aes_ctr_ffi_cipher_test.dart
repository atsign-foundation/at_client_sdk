@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:at_chops/at_chops_ffi.dart';
import 'package:at_commons/at_commons.dart' hide StringBuffer;
import 'package:test/test.dart';

Uint8List _hex(String s) {
  final Uint8List out = Uint8List(s.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(Uint8List b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

AESKey _keyFromHex(String hex) => AESKey(base64Encode(_hex(hex)));

/// NIST SP 800-38A F.5 uses one plaintext for every CTR vector.
const String _nistPlaintextHex = '6bc1bee22e409f96e93d7e117393172a'
    'ae2d8a571e03ac9c9eb76fac45af8e51'
    '30c81c46a35ce411e5fbc1191a0a52ef'
    'f69f2445df4f9b17ad2b417be66c3710';

const String _nistCounterHex = 'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff';

void main() {
  group('AesCtrFfiCipher', () {
    final StringBuffer loadedPath = StringBuffer();
    final DynamicLibrary? lib = tryLoadLibCrypto(loadedPath: loadedPath);

    setUpAll(() {
      if (lib != null) {
        // ignore: avoid_print
        print('libcrypto loaded from: ${loadedPath.toString()}');
      }
    });

    AesCtrFfiCipher makeCipher(AESKey key, InitialisationVector iv) {
      if (lib == null) fail('libcrypto not available on this host');
      return AesCtrFfiCipher.fromLib(lib, key, iv);
    }

    /// NIST SP 800-38A F.5.1 / F.5.3 / F.5.5, verified against
    /// `openssl enc -aes-<n>-ctr`. These pin the keystream itself, so a wrong
    /// counter-block interpretation fails here rather than at the far end of a
    /// tunnel.
    group('NIST SP 800-38A vectors', () {
      const Map<String, List<String>> vectors = <String, List<String>>{
        'AES-128': <String>[
          '2b7e151628aed2a6abf7158809cf4f3c',
          '874d6191b620e3261bef6864990db6ce'
              '9806f66b7970fdff8617187bb9fffdff'
              '5ae4df3edbd5d35e5b4f09020db03eab'
              '1e031dda2fbe03d1792170a0f3009cee',
        ],
        'AES-192': <String>[
          '8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b',
          '1abc932417521ca24f2b0459fe7e6e0b'
              '090339ec0aa6faefd5ccc2c6f4ce8e94'
              '1e36b26bd1ebc670d1bd1d665620abf7'
              '4f78a7f6d29809585a97daec58c6b050',
        ],
        'AES-256': <String>[
          '603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4',
          '601ec313775789a5b7a7f504bbf3d228'
              'f443e3ca4d62b59aca84e990cacaf5c5'
              '2b0930daa23de94ce87017ba2d84988d'
              'dfc9c58db67aada613c2dd08457941a6',
        ],
      };

      vectors.forEach((String name, List<String> vector) {
        test('$name matches the published ciphertext', () {
          final AesCtrFfiCipher cipher = makeCipher(_keyFromHex(vector[0]),
              InitialisationVector(_hex(_nistCounterHex)));
          try {
            expect(_toHex(cipher.update(_hex(_nistPlaintextHex))), vector[1]);
          } finally {
            cipher.dispose();
          }
        });

        test('$name decrypts with a second instance', () {
          final AesCtrFfiCipher cipher = makeCipher(_keyFromHex(vector[0]),
              InitialisationVector(_hex(_nistCounterHex)));
          try {
            expect(_toHex(cipher.update(_hex(vector[1]))), _nistPlaintextHex);
          } finally {
            cipher.dispose();
          }
        });
      });
    });

    /// The reason this class exists: `srv` hands it whatever the socket
    /// delivers, so the keystream offset must survive chunk boundaries that
    /// fall inside an AES block.
    test('chunked update equals one-shot update at any chunk size', () {
      final AESKey key = AESKey.generate(32);
      final InitialisationVector iv = InitialisationVector.random(16);
      final Uint8List plaintext =
          Uint8List.fromList(List<int>.generate(4096, (int i) => i & 0xff));

      final AesCtrFfiCipher oneShot = makeCipher(key, iv);
      final Uint8List expected;
      try {
        expected = oneShot.update(plaintext);
      } finally {
        oneShot.dispose();
      }

      for (final int chunk in <int>[1, 7, 16, 1000]) {
        final AesCtrFfiCipher cipher = makeCipher(key, iv);
        try {
          final BytesBuilder actual = BytesBuilder(copy: false);
          for (int i = 0; i < plaintext.length; i += chunk) {
            final int end = (i + chunk).clamp(0, plaintext.length);
            actual.add(cipher.update(Uint8List.sublistView(plaintext, i, end)));
          }
          expect(actual.takeBytes(), expected,
              reason: 'chunk size $chunk diverged from the one-shot keystream');
        } finally {
          cipher.dispose();
        }
      }
    });

    test('empty input is a no-op and does not advance the keystream', () {
      final AESKey key = AESKey.generate(32);
      final InitialisationVector iv = InitialisationVector.random(16);
      final AesCtrFfiCipher cipher = makeCipher(key, iv);
      try {
        expect(cipher.update(Uint8List(0)), isEmpty);
        final Uint8List after = cipher.update(_hex(_nistPlaintextHex));

        final AesCtrFfiCipher control = makeCipher(key, iv);
        try {
          expect(after, control.update(_hex(_nistPlaintextHex)));
        } finally {
          control.dispose();
        }
      } finally {
        cipher.dispose();
      }
    });

    test('a growing chunk stays correct across buffer reallocation', () {
      // The scratch buffers only ever grow, so this walks every reallocation
      // path in one instance.
      final AESKey key = AESKey.generate(32);
      final InitialisationVector iv = InitialisationVector.random(16);
      final Uint8List plaintext =
          Uint8List.fromList(List<int>.generate(2080, (int i) => i & 0xff));

      final AesCtrFfiCipher oneShot = makeCipher(key, iv);
      final Uint8List expected;
      try {
        expected = oneShot.update(plaintext);
      } finally {
        oneShot.dispose();
      }

      final AesCtrFfiCipher cipher = makeCipher(key, iv);
      try {
        final BytesBuilder actual = BytesBuilder(copy: false);
        int offset = 0;
        for (int size = 1; offset < plaintext.length; size *= 2) {
          final int end = (offset + size).clamp(0, plaintext.length);
          actual.add(
              cipher.update(Uint8List.sublistView(plaintext, offset, end)));
          offset = end;
        }
        expect(actual.takeBytes(), expected);
      } finally {
        cipher.dispose();
      }
    });

    group('lifecycle', () {
      test('update after dispose throws', () {
        final AesCtrFfiCipher cipher =
            makeCipher(AESKey.generate(32), InitialisationVector.random(16));
        cipher.dispose();
        expect(() => cipher.update(Uint8List(4)), throwsA(isA<StateError>()));
      });

      test('dispose is idempotent', () {
        final AesCtrFfiCipher cipher =
            makeCipher(AESKey.generate(32), InitialisationVector.random(16));
        cipher.dispose();
        expect(cipher.dispose, returnsNormally);
      });

      test('dispose before any update releases cleanly', () {
        final AesCtrFfiCipher cipher =
            makeCipher(AESKey.generate(32), InitialisationVector.random(16));
        expect(cipher.dispose, returnsNormally);
      });
    });

    group('construction rejects bad parameters', () {
      test('an IV that is not 16 bytes throws', () {
        for (final int length in <int>[0, 12, 15, 17, 32]) {
          expect(
              () => makeCipher(
                  AESKey.generate(32), InitialisationVector(Uint8List(length))),
              throwsA(isA<AtEncryptionException>()),
              reason: '$length-byte IV was accepted');
        }
      });

      test('a key that is not 16, 24 or 32 bytes throws', () {
        for (final int length in <int>[8, 20, 31, 33, 64]) {
          expect(
              () => makeCipher(AESKey(base64Encode(Uint8List(length))),
                  InitialisationVector.random(16)),
              throwsA(isA<AtEncryptionException>()),
              reason: '$length-byte key was accepted');
        }
      });
    });
  });
}
