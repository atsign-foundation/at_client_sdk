import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/envelope_exceptions.dart';
import 'package:at_client_wasm/src/keys/key_envelope.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:test/test.dart';

void main() {
  const codec = KeyEnvelopeCodec();

  final prf = PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));
  final prfOther =
      PrfSecret(Uint8List.fromList(List.generate(32, (i) => i + 64)));
  final prfWrong =
      PrfSecret(Uint8List.fromList(List.generate(32, (i) => i + 1)));

  final plaintext = {'test': 'data', 'number': 42};

  Future<Map<String, dynamic>> sealedJson(List<UnlockSecret> secrets) async =>
      jsonDecode(utf8.decode(await codec.seal('@alice', plaintext, secrets)))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> openJson(
          Map<String, dynamic> json, UnlockSecret secret,
          {String atSign = '@alice'}) async =>
      (await codec.open(atSign, utf8.encode(jsonEncode(json)), secret))
          .plaintext;

  void flipFirstByte(Map<String, dynamic> parent, String key) {
    final bytes = base64Decode(parent[key] as String);
    bytes[0] ^= 1;
    parent[key] = base64Encode(bytes);
  }

  Map<String, dynamic> unlock(Map<String, dynamic> json) =>
      (json['unlocks'] as List)[0] as Map<String, dynamic>;

  group('round trip', () {
    test('prf', () async {
      final envelope = await codec.seal('@alice', plaintext, [prf]);
      expect((await codec.open('@alice', envelope, prf)).plaintext, plaintext);
    });

    test('both unlocks of one envelope open the same content', () async {
      final envelope = await codec.seal('@alice', plaintext, [prf, prfOther]);
      expect((await codec.open('@alice', envelope, prf)).plaintext, plaintext);
      expect((await codec.open('@alice', envelope, prfOther)).plaintext,
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
      final json = await sealedJson([prf, prfOther]);
      final reordered = reverse(json) as Map<String, dynamic>;
      expect(await openJson(reordered, prf), plaintext);
      expect(await openJson(reordered, prfOther), plaintext);
    });

    test('reseal keeps the unlocks and opens with both', () async {
      final envelope = await codec.seal('@alice', plaintext, [prf, prfOther]);
      final replacement = {'test': 'updated', 'number': 43};
      final resealed =
          await (await codec.open('@alice', envelope, prf)).reseal(replacement);

      expect(jsonDecode(utf8.decode(resealed))['unlocks'],
          jsonDecode(utf8.decode(envelope))['unlocks']);
      expect(
          (await codec.open('@alice', resealed, prf)).plaintext, replacement);
      expect((await codec.open('@alice', resealed, prfOther)).plaintext,
          replacement);
    });

    test('seal with no secrets throws ArgumentError', () {
      expect(() => codec.seal('@alice', plaintext, []),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('wrong secret', () {
    test('wrong prf -> EnvelopeUnlockFailedException', () async {
      await expectLater(openJson(await sealedJson([prf]), prfWrong),
          throwsA(isA<EnvelopeUnlockFailedException>()));
    });

    test('an envelope with no prf unlock -> NoMatchingUnlockException',
        () async {
      final json = await sealedJson([prf]);
      json['unlocks'] = [];
      await expectLater(
          openJson(json, prf), throwsA(isA<NoMatchingUnlockException>()));
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
    for (final (name, tamper) in [
      ('unknown v', (Map<String, dynamic> j) => j['v'] = 2),
      (
        'unknown content.alg',
        (Map<String, dynamic> j) => j['content']['alg'] = 'A128GCM'
      ),
      (
        'unknown kind',
        (Map<String, dynamic> j) =>
            (j['unlocks'] as List).add({...unlock(j), 'kind': 'largeBlob'})
      ),
      (
        'a passphrase unlock',
        (Map<String, dynamic> j) => (j['unlocks'] as List).add({
              'kind': 'passphrase',
              'kdf': {
                'alg': 'pbkdf2-sha256',
                'salt': unlock(j)['kdf']['salt'],
                'params': {'alg': 'pbkdf2-sha256', 'iterations': 1000},
              },
              'wrap': unlock(j)['wrap'],
            })
      ),
      (
        'prf with a non-hkdf alg',
        (Map<String, dynamic> j) => unlock(j)['kdf']['alg'] = 'argon2id'
      ),
      (
        'malformed base64',
        (Map<String, dynamic> j) => j['content']['ct'] = '!!not base64!!'
      ),
      (
        'mistyped field',
        (Map<String, dynamic> j) => unlock(j)['wrap']['iv'] = 12
      ),
      ('unlocks not a list', (Map<String, dynamic> j) => j['unlocks'] = {}),
    ]) {
      test(name, () async {
        final json = await sealedJson([prf]);
        tamper(json);
        await expectLater(
            openJson(json, prf), throwsA(isA<UnsupportedEnvelopeException>()));
      });
    }

    test('not JSON', () async {
      await expectLater(codec.open('@alice', utf8.encode('not json'), prf),
          throwsA(isA<UnsupportedEnvelopeException>()));
    });
  });

  group('withUnlock', () {
    test('adds unlock and preserves plaintext', () async {
      final envelope = await codec.seal('@alice', plaintext, [prfOther]);
      final opened = await codec.open('@alice', envelope, prfOther);

      final modifiedEnvelope = await opened.withUnlock(prf);

      expect((await codec.open('@alice', modifiedEnvelope, prf)).plaintext,
          plaintext);
      expect((await codec.open('@alice', modifiedEnvelope, prfOther)).plaintext,
          plaintext);

      final modifiedJson = jsonDecode(utf8.decode(modifiedEnvelope));
      expect((modifiedJson['unlocks'] as List).length, 2);

      final originalJson = jsonDecode(utf8.decode(envelope));
      expect(modifiedJson['unlocks'][0], originalJson['unlocks'][0]);
    });
  });

  group('mergeUnlocksFrom', () {
    test('merges unlocks successfully keeping content identical', () async {
      final serverEnvelope = await codec.seal('@alice', plaintext, [prfOther]);

      final openedServer = await codec.open('@alice', serverEnvelope, prfOther);
      final localEnvelope = await openedServer.withUnlock(prf);
      final openedLocal = await codec.open('@alice', localEnvelope, prf);

      final mergedEnvelope = await openedLocal.mergeUnlocksFrom(serverEnvelope);

      final mergedJson = jsonDecode(utf8.decode(mergedEnvelope));
      final serverJson = jsonDecode(utf8.decode(serverEnvelope));

      expect(mergedJson['content']['iv'], serverJson['content']['iv']);
      expect(mergedJson['content']['ct'], serverJson['content']['ct']);

      expect((await codec.open('@alice', mergedEnvelope, prf)).plaintext,
          plaintext);
      expect((await codec.open('@alice', mergedEnvelope, prfOther)).plaintext,
          plaintext);
    });

    test('survives server reseal', () async {
      final serverEnvelope = await codec.seal('@alice', plaintext, [prfOther]);
      final openedServer = await codec.open('@alice', serverEnvelope, prfOther);

      final localEnvelope = await openedServer.withUnlock(prf);
      final openedLocal = await codec.open('@alice', localEnvelope, prf);

      final replacement = {'new': 'data'};
      final resealedServer = await openedServer.reseal(replacement);

      final mergedEnvelope = await openedLocal.mergeUnlocksFrom(resealedServer);

      expect((await codec.open('@alice', mergedEnvelope, prf)).plaintext,
          replacement);
    });

    test('idempotent merge yields no duplicates', () async {
      final serverEnvelope = await codec.seal('@alice', plaintext, [prfOther]);
      final openedServer = await codec.open('@alice', serverEnvelope, prfOther);

      final localEnvelope = await openedServer.withUnlock(prf);
      final openedLocal = await codec.open('@alice', localEnvelope, prf);

      final merged1 = await openedLocal.mergeUnlocksFrom(serverEnvelope);
      final openedMerged = await codec.open('@alice', merged1, prf);
      final merged2 = await openedMerged.mergeUnlocksFrom(serverEnvelope);

      final merged2Json = jsonDecode(utf8.decode(merged2));
      expect((merged2Json['unlocks'] as List).length, 2);
    });

    test('different content key throws EnvelopeContentKeyMismatchException',
        () async {
      final serverEnvelope = await codec.seal('@alice', plaintext, [prfOther]);
      final otherEnvelope = await codec.seal('@alice', plaintext, [prf]);

      final openedOther = await codec.open('@alice', otherEnvelope, prf);

      await expectLater(openedOther.mergeUnlocksFrom(serverEnvelope),
          throwsA(isA<EnvelopeContentKeyMismatchException>()));
    });

    test('different atSign throws EnvelopeAtSignMismatchException', () async {
      final serverEnvelope = await codec.seal('@bob', plaintext, [prfOther]);
      final localEnvelope = await codec.seal('@alice', plaintext, [prf]);

      final openedLocal = await codec.open('@alice', localEnvelope, prf);

      await expectLater(openedLocal.mergeUnlocksFrom(serverEnvelope),
          throwsA(isA<EnvelopeAtSignMismatchException>()));
    });
  });

  group('golden', () {
    test('read test/fixtures/envelope_v1_golden.json', () async {
      final file = File('test/fixtures/envelope_v1_golden.json');
      final goldenBytes = await file.readAsBytes();

      final goldenPrf =
          PrfSecret(Uint8List.fromList(List.generate(32, (i) => i)));

      final openedPrf = await codec.open('@golden', goldenBytes, goldenPrf);

      expect(openedPrf.plaintext,
          {"atSign": "@golden", "note": "at_client_wasm envelope v1 golden"});
    });
  });
}
