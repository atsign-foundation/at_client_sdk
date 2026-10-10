import 'dart:convert';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group(
      'A group of tests to verify AES encryption decryption with different key lengths',
      () {
    for (final keyLengthBytes in [16, 24, 32]) {
      test(
          'Test encryption and decryption for ${keyLengthBytes * 8} bit AES key',
          () async {
        var data = '🛠Hello\nWorld🛠\n123asdasd!@&^\'🛠';
        final aesCtr = AesCtrEncryptionAlgo(keyLengthBytes);
        var key = aesCtr.generateKey();
        var iv = InitialisationVector.random(16);
        var encryptedBytes =
            await aesCtr.encrypt(utf8.encode(data), key, iv: iv);
        var decryptedBytes = await aesCtr.decrypt(encryptedBytes, key, iv: iv);
        expect(utf8.decode(decryptedBytes), data);
      });
    }

    test('Test an IV of the wrong length is rejected', () async {
      final aesCtr = AesCtrEncryptionAlgo(32);
      final key = aesCtr.generateKey();
      final shortIv = InitialisationVector.random(12);
      expect(() => aesCtr.encrypt(utf8.encode('Hello World'), key, iv: shortIv),
          throwsA(isA<AtEncryptionException>()));
      expect(() => aesCtr.decrypt(utf8.encode('Hello World'), key, iv: shortIv),
          throwsA(isA<AtDecryptionException>()));
    });

    test('Test the legacy all-zeroes IV round-trips', () async {
      final aesCtr = AesCtrEncryptionAlgo(32);
      final key = aesCtr.generateKey();
      final iv = InitialisationVector.legacy();
      final enc = await aesCtr.encrypt(utf8.encode('Hello World'), key, iv: iv);
      expect(
          utf8.decode(await aesCtr.decrypt(enc, key, iv: iv)), 'Hello World');
    });

    test('Test unsupported key length is rejected at construction', () {
      expect(() => AesCtrEncryptionAlgo(20),
          throwsA(isA<AtEncryptionException>()));
    });

    test(
        'Test a key whose length differs from the configured length is rejected',
        () async {
      final aesCtr = AesCtrEncryptionAlgo(32);
      final key = AesCtrEncryptionAlgo(16).generateKey();
      final iv = InitialisationVector.random(16);
      expect(() => aesCtr.encrypt(utf8.encode('Hello World'), key, iv: iv),
          throwsA(isA<AtEncryptionException>()));
      expect(() => aesCtr.decrypt(utf8.encode('Hello World'), key, iv: iv),
          throwsA(isA<AtDecryptionException>()));
    });
  });
}
