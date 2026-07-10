import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart'
    as passphrase_envelope;
import 'package:at_chops/at_chops.dart' show HashingAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysPassphraseCrypto', () {
    test('encrypts and decrypts with argon2id', () async {
      const plainAtKeys = '{"version":1,"keys":[]}';
      final crypto = passphrase_envelope.AtKeysPassphraseCrypto.fromHashingAlgorithm(
        HashingAlgoType.argon2id,
      );

      final encrypted = await crypto.encrypt(plainAtKeys, 'passphrase');
      final decrypted = await crypto.decrypt(encrypted, 'passphrase');

      expect(encrypted.hashingAlgoType, HashingAlgoType.argon2id);
      expect(decrypted, plainAtKeys);
    });
  });

  group('AtKeysPassphraseEnvelopeCodec', () {
    const codec = passphrase_envelope.AtKeysPassphraseEnvelopeCodec();

    Future<Map<String, dynamic>> envelopeFor(String plaintext) async {
      final envelope =
          await passphrase_envelope.AtKeysPassphraseCrypto.fromHashingAlgorithm(
        HashingAlgoType.argon2id,
      ).encrypt(plaintext, 'right');
      return Map<String, dynamic>.from(
        (envelope.toJson())..removeWhere((_, value) => value == null),
      );
    }

    test('returns the map unchanged when it is not an envelope', () async {
      final json = {'not': 'an-envelope'};
      expect(await codec.decode(json), same(json));
    });

    test('throws when an envelope has no passphrase', () {
      expect(
        () => codec.decode({'iv': 'aXY=', 'content': 'x'}),
        throwsA(isA<AtDecryptionException>()),
      );
    });

    test('throws when an envelope has no hashing algo type', () {
      expect(
        () => codec.decode(
          {'iv': 'aXY=', 'content': 'x'},
          passPhrase: 'right',
        ),
        throwsA(isA<AtDecryptionException>()),
      );
    });

    test('throws AtDecryptionException on an incorrect passphrase', () async {
      final envelope = await envelopeFor('{"version":1,"keys":[]}');
      expect(
        () => codec.decode(envelope, passPhrase: 'wrong'),
        throwsA(isA<AtDecryptionException>()),
      );
    });

    test('wraps non-object decrypted payloads as decryption failures',
        () async {
      // '42' decrypts to a JSON number, not an object.
      final envelope = await envelopeFor('42');
      expect(
        () => codec.decode(envelope, passPhrase: 'right'),
        throwsA(isA<AtDecryptionException>()),
      );
    });
  });
}
