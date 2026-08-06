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

  group('version 1 salting', () {
    const codec = AtKeysPassphraseEnvelopeCodec();
    const doc = '{"aesPkamPublicKey":"abc","x":1}';

    test('what gets written carries a version, a salt and its costs', () async {
      final e = jsonDecode(await codec.encode(doc, 'right'))
          as Map<String, dynamic>;

      expect(e['v'], 1);
      expect(base64Decode(e['salt'] as String).length,
          AtKeysPassphraseEnvelopeCodec.saltLength);
      expect(e['kdfParams'],
          {'memory': 19456, 'iterations': 2, 'parallelism': 1});
      expect(await codec.decode(e, passPhrase: 'right'), jsonDecode(doc));
    });

    test('two encodes of one document under one passphrase share no salt',
        () async {
      final a =
          jsonDecode(await codec.encode(doc, 'same')) as Map<String, dynamic>;
      final b =
          jsonDecode(await codec.encode(doc, 'same')) as Map<String, dynamic>;

      // The defect this format exists to fix: without a per-file salt the AES
      // key is a pure function of the passphrase, so every user who picks
      // "same" shares a key and one precomputation table serves all of them.
      expect(a['salt'], isNot(b['salt']));
      expect(await codec.decode(a, passPhrase: 'same'), jsonDecode(doc));
      expect(await codec.decode(b, passPhrase: 'same'), jsonDecode(doc));
    });

    test('the costs are read back off the file, not assumed', () async {
      final e =
          jsonDecode(await codec.encode(doc, 'right')) as Map<String, dynamic>;
      // Editing a cost changes the derived key, so the file no longer opens.
      // If this passes, decode is deriving with its own defaults and would
      // break the moment those defaults are raised.
      final tampered = Map<String, dynamic>.from(e)
        ..['kdfParams'] = {'memory': 20000, 'iterations': 2, 'parallelism': 1};
      expect(() => codec.decode(tampered, passPhrase: 'right'),
          throwsA(isA<AtDecryptionException>()));
    });

    test('an envelope version this build has no code for is refused', () {
      expect(
        () => codec.decode({
          'v': 99,
          'iv': 'aXYaXYaXYaXYaXYa',
          'content': 'x',
          'hashingAlgoType': 'argon2id',
        }, passPhrase: 'right'),
        throwsA(isA<AtDecryptionException>().having(
            (e) => '$e', 'message', contains('no code for'))),
        reason: 'falling back to the legacy derivation would report a version '
            'mismatch as a wrong passphrase',
      );
    });

    test('a version 1 envelope without a salt is refused', () {
      expect(
        () => codec.decode({
          'v': 1,
          'iv': 'aXYaXYaXYaXYaXYa',
          'content': 'x',
          'hashingAlgoType': 'argon2id',
        }, passPhrase: 'right'),
        throwsA(isA<AtDecryptionException>()),
      );
    });

    test('a single-pass hash cannot be written as a version 1 envelope', () {
      expect(
        () => codec.encode(doc, 'right',
            hashingAlgoType: HashingAlgoType.md5),
        throwsA(isA<AtException>()),
      );
    });
  });

  group('legacy envelopes still open', () {
    const codec = AtKeysPassphraseEnvelopeCodec();

    // Captured from this codec BEFORE the salt was introduced. They are the
    // whole compatibility guarantee: the passphrase is the user's and nothing
    // here can re-derive these documents without it, so the old unsalted
    // derivation has to keep working exactly.
    const asciiEnvelope =
        '{"content":"YuP+RgHL2zFSwMUgLlDY9xFdmIZsFZ1jd6xDetH15DURPbRmE1pYoci'
        'akFgWpsr3","iv":"vnw2SVssTWrIwibp2NvUVw==","hashingAlgoType":"argon2id"}';
    const nonAsciiEnvelope =
        '{"content":"nvu64grwzBfdp5iGdA83QHvcqXlL9rmpQ8A0V7jc/iztFlbTJG4A/yg'
        'pXqxo9Sjl","iv":"Wn8W314zbPbZEQAU2RuG+g==","hashingAlgoType":"argon2id"}';
    const expected = {'aesPkamPublicKey': 'abc', 'x': 1};

    test('an ASCII-passphrase file written before the salt existed', () async {
      expect(
        await codec.decode(
            jsonDecode(asciiEnvelope) as Map<String, dynamic>,
            passPhrase: 'plain-ascii'),
        expected,
      );
    });

    test('and a non-ASCII one, which pins the UTF-16 salt', () async {
      // The legacy salt is `password.codeUnits` — UTF-16. Re-encoding it as
      // UTF-8 would be the obvious tidy-up and would silently orphan every
      // file whose owner used a non-ASCII passphrase.
      expect(
        await codec.decode(
            jsonDecode(nonAsciiEnvelope) as Map<String, dynamic>,
            passPhrase: 'passwörd-☃'),
        expected,
      );
    });

    test('the legacy form can still be written deliberately', () async {
      final e = jsonDecode(await codec.encode('{"a":1}', 'pw',
          legacyUnsaltedDerivation: true)) as Map<String, dynamic>;
      expect(e.containsKey('v'), isFalse);
      expect(e.containsKey('salt'), isFalse);
      expect(await codec.decode(e, passPhrase: 'pw'), {'a': 1});
    });
  });
}
