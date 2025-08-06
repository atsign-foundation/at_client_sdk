import 'package:at_chops/src/key/impl/aes_key.dart';
import 'package:encrypt/encrypt.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests for AES Key generation', () {
    test('Test generate AESKey - 128 bit', () {
      final aesKey = AESKey.generate(16);
      expect(Key.fromBase64(aesKey.key).length, 16);
    });
    test('Test generate AESKey - 128 bit random generation', () {
      final aesKey_1 = AESKey.generate(16);
      final aesKey_2 = AESKey.generate(16);
      expect(aesKey_1, isNot(aesKey_2));
    });
    test('Test generate AESKey - 256 bit', () {
      final aesKey = AESKey.generate(32);
      expect(Key.fromBase64(aesKey.key).length, 32);
    });
    test('Test generate AESKey - 256 bit random generation', () {
      final aesKey_1 = AESKey.generate(32);
      final aesKey_2 = AESKey.generate(32);
      expect(aesKey_1, isNot(aesKey_2));
    });
    test('check random key generated length for 128 bit key', () {
      final aesKey = AESKey.generate(16);
      expect(aesKey.getLength(), 16);
    });
    test('check random key generated  length for 192 bit key', () {
      final aesKey = AESKey.generate(24);
      expect(aesKey.getLength(), 24);
    });
    test('check random key generated  length for 256 bit key', () {
      final aesKey = AESKey.generate(32);
      expect(aesKey.getLength(), 32);
    });
    test('verify key length for 256 bit key constructed from string', () {
      final aesKey_1 = AESKey.generate(32);
      final aesKey = AESKey(aesKey_1.key);
      expect(aesKey.getLength(), 32);
    });
    test('verify key length for 192 bit key constructed from string', () {
      final aesKey_1 = AESKey.generate(24);
      final aesKey = AESKey(aesKey_1.key);
      expect(aesKey.getLength(), 24);
    });
    test('verify key length for 128 bit key constructed from string', () {
      final aesKey_1 = AESKey.generate(16);
      final aesKey = AESKey(aesKey_1.key);
      expect(aesKey.getLength(), 16);
    });
  });
}
