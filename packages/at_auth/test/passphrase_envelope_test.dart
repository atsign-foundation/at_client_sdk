import 'dart:convert';

import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';
import 'package:at_chops/at_chops.dart' show HashingAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysPassphraseEnvelopeCodec', () {
    const codec = AtKeysPassphraseEnvelopeCodec();

    Future<Map<String, dynamic>> envelopeFor(String plaintext) async {
      return jsonDecode(await codec.encode(plaintext, 'right'))
          as Map<String, dynamic>;
    }

    test('encode/decode round-trips with argon2id', () async {
      const plainAtKeys = '{"version":1,"keys":[]}';
      final envelope = await envelopeFor(plainAtKeys);

      expect(envelope['hashingAlgoType'], HashingAlgoType.argon2id.name);
      expect(codec.isEnvelope(envelope), isTrue);
      expect(
        await codec.decode(envelope, passPhrase: 'right'),
        jsonDecode(plainAtKeys),
      );
    });

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
