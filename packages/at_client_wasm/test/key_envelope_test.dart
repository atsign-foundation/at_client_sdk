import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client_wasm/src/keys/envelope_exceptions.dart';
import 'package:at_client_wasm/src/keys/key_envelope.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:test/test.dart';

void main() {
  const argon2idCheap =
      Argon2idParams(memoryKiB: 64, iterations: 1, parallelism: 1);
  const pbkdf2Params = Pbkdf2Sha256Params(iterations: 1000);

  const codecArgon = KeyEnvelopeCodec(passphraseParams: argon2idCheap);
  const codecPbkdf2 = KeyEnvelopeCodec(passphraseParams: pbkdf2Params);

  final prf = PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));
  final prfWrong =
      PrfSecret(Uint8List.fromList(List.generate(32, (i) => i + 1)));
  final passphrase = PassphraseSecret('this-is-a-passphrase');
  final passphraseWrong = PassphraseSecret('wrong-passphrase');

  final plaintext = {'test': 'data', 'number': 42};

  Future<Map<String, dynamic>> sealedJson(List<UnlockSecret> secrets) async =>
      jsonDecode(
              utf8.decode(await codecArgon.seal('@alice', plaintext, secrets)))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> openJson(
          Map<String, dynamic> json, UnlockSecret secret,
          {String atSign = '@alice'}) async =>
      (await codecArgon.open(atSign, utf8.encode(jsonEncode(json)), secret))
          .plaintext;

  void flipFirstByte(Map<String, dynamic> parent, String key) {
    final bytes = base64Decode(parent[key] as String);
    bytes[0] ^= 1;
    parent[key] = base64Encode(bytes);
  }

  Map<String, dynamic> unlock(Map<String, dynamic> json) =>
      (json['unlocks'] as List)[0] as Map<String, dynamic>;

  group('round trip', () {
    for (final (name, codec, secret) in [
      ('prf', codecArgon, prf as UnlockSecret),
      ('passphrase/argon2id', codecArgon, passphrase),
      ('passphrase/pbkdf2', codecPbkdf2, passphrase),
    ]) {
      test(name, () async {
        final envelope = await codec.seal('@alice', plaintext, [secret]);
        expect((await codec.open('@alice', envelope, secret)).plaintext,
            plaintext);
      });
    }

    test('both unlocks of one envelope open the same content', () async {
      final envelope =
          await codecArgon.seal('@alice', plaintext, [prf, passphrase]);
      expect((await codecArgon.open('@alice', envelope, prf)).plaintext,
          plaintext);
      expect((await codecArgon.open('@alice', envelope, passphrase)).plaintext,
          plaintext);
    });

    test('pbkdf2 params travel in the record to an argon2id codec', () async {
      final envelope =
          await codecPbkdf2.seal('@alice', plaintext, [passphrase]);
      expect((await codecArgon.open('@alice', envelope, passphrase)).plaintext,
          plaintext);
    });

    test('an envelope re-serialized with reordered keys still opens', () async {
      Object? reverse(Object? node) => switch (node) {
            Map() => <String, Object?>{
                for (final key in node.keys.toList().reversed)
                  key: reverse(node[key])
              },
            List() => [for (final e in node) reverse(e)],
            _ => node,
          };
      final json = await sealedJson([prf, passphrase]);
      final reordered = reverse(json) as Map<String, dynamic>;
      expect(await openJson(reordered, prf), plaintext);
      expect(await openJson(reordered, passphrase), plaintext);
    });

    test('reseal keeps the unlocks and opens with both', () async {
      final envelope =
          await codecArgon.seal('@alice', plaintext, [prf, passphrase]);
      final replacement = {'test': 'updated', 'number': 43};
      final resealed = await (await codecArgon.open('@alice', envelope, prf))
          .reseal(replacement);

      expect(jsonDecode(utf8.decode(resealed))['unlocks'],
          jsonDecode(utf8.decode(envelope))['unlocks']);
      expect((await codecArgon.open('@alice', resealed, prf)).plaintext,
          replacement);
      expect((await codecArgon.open('@alice', resealed, passphrase)).plaintext,
          replacement);
    });

    test('seal with no secrets throws ArgumentError', () {
      expect(() => codecArgon.seal('@alice', plaintext, []),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('wrong secret', () {
    test('wrong prf -> EnvelopeUnlockFailedException', () async {
      await expectLater(openJson(await sealedJson([prf]), prfWrong),
          throwsA(isA<EnvelopeUnlockFailedException>()));
    });

    test('wrong passphrase -> EnvelopeUnlockFailedException', () async {
      await expectLater(
          openJson(await sealedJson([passphrase]), passphraseWrong),
          throwsA(isA<EnvelopeUnlockFailedException>()));
    });

    test('prf against a passphrase-only envelope -> NoMatchingUnlockException',
        () async {
      await expectLater(openJson(await sealedJson([passphrase]), prf),
          throwsA(isA<NoMatchingUnlockException>()));
    });
  });

  group('tampering fails authentication', () {
    for (final (name, tamper) in [
      (
        'content.ct',
        (Map<String, dynamic> j) => flipFirstByte(j['content'], 'ct')
      ),
      (
        'content.iv',
        (Map<String, dynamic> j) => flipFirstByte(j['content'], 'iv')
      ),
      (
        'wrap.ct',
        (Map<String, dynamic> j) => flipFirstByte(unlock(j)['wrap'], 'ct')
      ),
      (
        'wrap.iv',
        (Map<String, dynamic> j) => flipFirstByte(unlock(j)['wrap'], 'iv')
      ),
      (
        'kdf.salt',
        (Map<String, dynamic> j) => flipFirstByte(unlock(j)['kdf'], 'salt')
      ),
    ]) {
      test(name, () async {
        final json = await sealedJson([prf]);
        tamper(json);
        await expectLater(
            openJson(json, prf), throwsA(isA<EnvelopeUnlockFailedException>()));
      });
    }

    test('kdf.params', () async {
      final json = await sealedJson([passphrase]);
      unlock(json)['kdf']['params']['t'] = 2;
      await expectLater(openJson(json, passphrase),
          throwsA(isA<EnvelopeUnlockFailedException>()));
    });

    test('atSign', () async {
      final json = await sealedJson([prf]);
      json['atSign'] = '@bob';
      await expectLater(
          openJson(json, prf), throwsA(isA<EnvelopeAtSignMismatchException>()));
      await expectLater(openJson(json, prf, atSign: '@bob'),
          throwsA(isA<EnvelopeUnlockFailedException>()));
    });
  });

  group('UnsupportedEnvelopeException', () {
    for (final (name, secret, tamper) in [
      (
        'unknown v',
        prf as UnlockSecret,
        (Map<String, dynamic> j) => j['v'] = 2
      ),
      (
        'unknown content.alg',
        prf,
        (Map<String, dynamic> j) => j['content']['alg'] = 'A128GCM'
      ),
      (
        'unknown kind',
        prf,
        (Map<String, dynamic> j) =>
            (j['unlocks'] as List).add({...unlock(j), 'kind': 'largeBlob'})
      ),
      (
        'unknown kdf alg',
        passphrase,
        (Map<String, dynamic> j) {
          unlock(j)['kdf']['alg'] = 'scrypt';
          unlock(j)['kdf']['params']['alg'] = 'scrypt';
        }
      ),
      (
        'kdf.alg disagreeing with params.alg',
        passphrase,
        (Map<String, dynamic> j) => unlock(j)['kdf']['alg'] = 'pbkdf2-sha256'
      ),
      (
        'prf with a non-hkdf alg',
        prf,
        (Map<String, dynamic> j) => unlock(j)['kdf']['alg'] = 'argon2id'
      ),
      (
        'malformed base64',
        prf,
        (Map<String, dynamic> j) => j['content']['ct'] = '!!not base64!!'
      ),
      (
        'mistyped field',
        prf,
        (Map<String, dynamic> j) => unlock(j)['wrap']['iv'] = 12
      ),
      (
        'unlocks not a list',
        prf,
        (Map<String, dynamic> j) => j['unlocks'] = {}
      ),
    ]) {
      test(name, () async {
        final json = await sealedJson([secret is PrfSecret ? prf : passphrase]);
        tamper(json);
        await expectLater(openJson(json, secret),
            throwsA(isA<UnsupportedEnvelopeException>()));
      });
    }

    test('not JSON', () async {
      await expectLater(codecArgon.open('@alice', utf8.encode('not json'), prf),
          throwsA(isA<UnsupportedEnvelopeException>()));
    });
  });
}
