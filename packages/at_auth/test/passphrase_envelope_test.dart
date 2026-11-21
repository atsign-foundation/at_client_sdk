import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/serialization/passphrase_envelope.dart';
import 'package:at_chops/at_chops.dart' show ArgonHashParams, HashingAlgoType;
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

typedef _Limits = AtKeysPassphraseEnvelopeCodec;

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
        throwsA(isA<AtKeysPassphraseException>()),
      );
    });

    test('throws when an envelope has no hashing algo type', () {
      expect(
        () => codec.decode(
          {'iv': 'aXY=', 'content': 'x'},
          passPhrase: 'right',
        ),
        throwsA(allOf(isA<AtDecryptionException>(),
            isNot(isA<AtKeysPassphraseException>()))),
      );
    });

    test('throws AtKeysPassphraseException on an incorrect passphrase',
        () async {
      final envelope = await envelopeFor('{"version":1,"keys":[]}');
      expect(
        () => codec.decode(envelope, passPhrase: 'wrong'),
        throwsA(isA<AtKeysPassphraseException>()),
      );
    });

    test(
        'an envelope version this build has no code for is not refused as '
        'a passphrase', () async {
      final envelope = await envelopeFor('{"version":1,"keys":[]}')
        ..['v'] = 3;
      expect(
        () => codec.decode(envelope, passPhrase: 'right'),
        throwsA(allOf(
            isA<AtDecryptionException>().having((e) => e.message, 'message',
                contains('envelope version this build has no code for')),
            isNot(isA<AtKeysPassphraseException>()))),
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

  group('a refusal for anything but the passphrase is not a passphrase refusal',
      () {
    const codec = AtKeysPassphraseEnvelopeCodec();
    final notThePassphrase = throwsA(allOf(
        isA<AtDecryptionException>(), isNot(isA<AtKeysPassphraseException>())));

    /// A version 1 envelope under 'right', changed by [change].
    Future<Map<String, dynamic>> envelopeWith(
        void Function(Map<String, dynamic> envelope) change) async {
      final envelope = jsonDecode(await codec.encode('{"keys":[]}', 'right'))
          as Map<String, dynamic>;
      change(envelope);
      return envelope;
    }

    final cases = <String, void Function(Map<String, dynamic>)>{
      'an empty iv': (e) => e['iv'] = '',
      'an iv that is not base64': (e) => e['iv'] = '!not base64!',
      'no content': (e) => e.remove('content'),
      'content that is not base64': (e) => e['content'] = '!not base64!',
      'a hashingAlgoType this build has no code for': (e) =>
          e['hashingAlgoType'] = 'sha3',
      'no salt': (e) => e.remove('salt'),
      'a salt that is not base64': (e) => e['salt'] = '!not base64!',
      'no kdfParams': (e) => e.remove('kdfParams'),
      'a kdfParams cost below one': (e) =>
          (e['kdfParams'] as Map)['memory'] = 0,
      'a kdfParams memory below eight times its parallelism': (e) =>
          (e['kdfParams'] as Map)
            ..['memory'] = 8
            ..['parallelism'] = 2,
      'a kdfParams memory far above the limit': (e) =>
          (e['kdfParams'] as Map)['memory'] = 4000000000000,
    };
    for (final MapEntry(key: name, value: change) in cases.entries) {
      test(name, () async {
        final envelope = await envelopeWith(change);
        await expectLater(
            codec.decode(envelope, passPhrase: 'right'), notThePassphrase);
      });
    }

    group('kdfParams above a limit are refused before any derivation', () {
      final overLimit = <String, (Map<String, int>, String)>{
        'memory': (
          {'memory': _Limits.maxKdfMemory + 1, 'iterations': 1, 'parallelism': 1},
          'kdfParams.memory of at most ${_Limits.maxKdfMemory}'
        ),
        // NOTE: memory is small, so a codec without the limit derives quickly
        // and opens the envelope.
        'iterations': (
          {'memory': 8, 'iterations': _Limits.maxKdfIterations + 1, 'parallelism': 1},
          'kdfParams.iterations of at most ${_Limits.maxKdfIterations}'
        ),
        'parallelism': (
          {
            'memory': 8 * (_Limits.maxKdfParallelism + 1),
            'iterations': 1,
            'parallelism': _Limits.maxKdfParallelism + 1
          },
          'kdfParams.parallelism of at most ${_Limits.maxKdfParallelism}'
        ),
        'memory times iterations': (
          {'memory': _Limits.maxKdfMemory, 'iterations': 3, 'parallelism': 1},
          'kdfParams.memory times kdfParams.iterations of at most '
              '${_Limits.maxKdfWork}'
        ),
      };
      for (final MapEntry(key: name, value: (kdfParams, says))
          in overLimit.entries) {
        test(name, () async {
          final envelope =
              await envelopeWith((e) => e['kdfParams'] = kdfParams);
          await expectLater(
              codec.decode(envelope, passPhrase: 'right'),
              throwsA(allOf(
                  isA<AtDecryptionException>(),
                  isNot(isA<AtKeysPassphraseException>()),
                  predicate<AtDecryptionException>(
                      (e) => e.message.endsWith('must carry a $says'),
                      'says the limit'))));
        });
      }

      test('the most each limit allows is still opened', () async {
        final envelope = await envelopeWith((e) => e['kdfParams'] = {
              'memory': 8 * _Limits.maxKdfParallelism,
              'iterations': _Limits.maxKdfIterations,
              'parallelism': _Limits.maxKdfParallelism,
            });
        // NOTE: encoded under other costs, so the key differs; what matters
        // is that the costs are not refused.
        await expectLater(codec.decode(envelope, passPhrase: 'right'),
            throwsA(isA<AtKeysPassphraseException>()));
      });

      test('and encode refuses to write them', () async {
        await expectLater(
            codec.encode('{"keys":[]}', 'right',
                hashParams: ArgonHashParams()
                  ..memory = 8
                  ..iterations = _Limits.maxKdfIterations + 1
                  ..parallelism = 1),
            throwsA(isA<AtException>().having((e) => e.message, 'message',
                contains('kdfParams.iterations of at most'))));
      });
    });

    test(
        'a payload the right passphrase decrypts to something that is not a '
        'JSON object is a passphrase refusal', () async {
      for (final payload in ['42', 'not JSON']) {
        final envelope = jsonDecode(await codec.encode(payload, 'right'))
            as Map<String, dynamic>;
        await expectLater(codec.decode(envelope, passPhrase: 'right'),
            throwsA(isA<AtKeysPassphraseException>()),
            reason: 'decrypted to $payload');
      }
    });
  });

  group('version 1 salting', () {
    const codec = AtKeysPassphraseEnvelopeCodec();
    const doc = '{"aesPkamPublicKey":"abc","x":1}';

    test('what gets written carries a version, a salt and its costs', () async {
      final e =
          jsonDecode(await codec.encode(doc, 'right')) as Map<String, dynamic>;

      expect(e['v'], 1);
      expect(base64Decode(e['salt'] as String).length,
          AtKeysPassphraseEnvelopeCodec.saltLength);
      expect(
          e['kdfParams'], {'memory': 19456, 'iterations': 2, 'parallelism': 1});
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
        throwsA(isA<AtDecryptionException>()
            .having((e) => '$e', 'message', contains('no code for'))),
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
        () => codec.encode(doc, 'right', hashingAlgoType: HashingAlgoType.md5),
        throwsA(isA<AtException>()),
      );
    });

    test('a hashLength the envelope cannot record is refused at write time',
        () {
      // The envelope carries the salt and the three costs and nothing else,
      // so decode derives at ArgonHashParams's own default whatever was used
      // to write. Encoding at another length would produce a file that fails
      // to open as `passphrase may be incorrect`, naming the wrong cause.
      final varied = ArgonHashParams.owaspMinimum()..hashLength = 64;

      expect(
        () => codec.encode(doc, 'right', hashParams: varied),
        throwsA(
          isA<AtException>().having((e) => e.message, 'message',
              allOf(contains('hashLength'), contains('64'))),
        ),
        reason: 'the refusal has to name the parameter that differed, since '
            'the failure it prevents blames the passphrase instead',
      );
    });

    test('the default hashLength encodes and round-trips', () async {
      // The control arm for the refusal above: a params object that varies
      // nothing else must still be accepted, or the guard is refusing every
      // caller rather than the one it is for.
      final standard = ArgonHashParams.owaspMinimum();
      expect(standard.hashLength, ArgonHashParams().hashLength,
          reason: 'owaspMinimum raises the costs, not the key length - if it '
              'ever varies hashLength this control stops being one');

      final envelope =
          jsonDecode(await codec.encode(doc, 'right', hashParams: standard))
              as Map;

      expect(
        await codec.decode(envelope.cast<String, dynamic>(),
            passPhrase: 'right'),
        jsonDecode(doc),
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
        await codec.decode(jsonDecode(asciiEnvelope) as Map<String, dynamic>,
            passPhrase: 'plain-ascii'),
        expected,
      );
    });

    test('and a non-ASCII one, which pins the UTF-16 salt', () async {
      // The legacy salt is `password.codeUnits` — UTF-16. Re-encoding it as
      // UTF-8 would be the obvious tidy-up and would silently orphan every
      // file whose owner used a non-ASCII passphrase.
      expect(
        await codec.decode(jsonDecode(nonAsciiEnvelope) as Map<String, dynamic>,
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
