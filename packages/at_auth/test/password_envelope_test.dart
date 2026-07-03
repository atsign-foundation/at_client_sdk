import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart'
    as password_envelope;
import 'package:at_chops/at_chops.dart' show HashingAlgoType;
import 'package:test/test.dart';

void main() {
  group('AtKeysCrypto', () {
    test('encrypts and decrypts with argon2id', () async {
      const plainAtKeys = '{"version":1,"keys":[]}';
      final crypto = password_envelope.AtKeysCrypto.fromHashingAlgorithm(
        HashingAlgoType.argon2id,
      );

      final encrypted = await crypto.encrypt(plainAtKeys, 'passphrase');
      final decrypted = await crypto.decrypt(encrypted, 'passphrase');

      expect(encrypted.hashingAlgoType, HashingAlgoType.argon2id);
      expect(decrypted, plainAtKeys);
    });
  });
}
