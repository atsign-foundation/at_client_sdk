import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests to verify atKeys encryption and decryption', () {
    test(
        'A test to verify the encryption and decryption of atKeys using a passphrase with the argon2id algorithm',
        () async {
      String plainAtKeys = jsonEncode({
        'pkamPublicKey': 'dummy_pkam_public_key',
        'pkamPrivateKey': 'dummy_private_key'
      });
      String passPhrase = 'abcd';

      AtKeysCrypto atKeysCrypto =
          AtKeysCrypto.fromHashingAlgorithm(HashingAlgoType.argon2id);

      AtEncrypted atEncrypted =
          await atKeysCrypto.encrypt(plainAtKeys, passPhrase);
      expect(atEncrypted.content?.isNotEmpty, true);
      expect(atEncrypted.iv?.isNotEmpty, true);
      expect(atEncrypted.hashingAlgoType, HashingAlgoType.argon2id);

      String decryptedAtKeys =
          await atKeysCrypto.decrypt(atEncrypted, passPhrase);
      Map<String, dynamic> dummyAtKeys = jsonDecode(decryptedAtKeys);
      expect(dummyAtKeys['pkamPublicKey'], 'dummy_pkam_public_key');
      expect(dummyAtKeys['pkamPrivateKey'], 'dummy_private_key');
    });

    test('A test to verify the decryption fails when pass phrase is modified',
        () async {
      String plainAtKeys = jsonEncode({
        'pkamPublicKey': 'dummy_pkam_public_key',
        'pkamPrivateKey': 'dummy_private_key'
      });

      AtKeysCrypto atKeysCrypto =
          AtKeysCrypto.fromHashingAlgorithm(HashingAlgoType.argon2id);

      AtEncrypted atEncrypted = await atKeysCrypto.encrypt(plainAtKeys, 'abcd');
      expect(atEncrypted.content?.isNotEmpty, true);
      expect(atEncrypted.iv?.isNotEmpty, true);
      expect(atEncrypted.hashingAlgoType, HashingAlgoType.argon2id);

      expect(() async => await atKeysCrypto.decrypt(atEncrypted, 'abcde'),
          throwsA(predicate((dynamic e) => e is ArgumentError)));
    });
  });
}
