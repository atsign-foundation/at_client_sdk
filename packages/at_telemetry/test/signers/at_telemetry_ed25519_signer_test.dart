import 'dart:convert';
import 'dart:math';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
  group('AtTelemetryEd25519Signer', () {
    test('derives the same key from the same seed', () async {
      final List<int> seed = List<int>.generate(32, (int index) => index);
      final AtTelemetryEd25519Signer first =
          await AtTelemetryEd25519Signer.fromSeed(seed);
      final AtTelemetryEd25519Signer second =
          await AtTelemetryEd25519Signer.fromSeed(seed);

      expect(first.publicKey, second.publicKey);
      expect(first.publicKey, hasLength(32));
      expect(first.seed, seed);
    });

    // RFC 8032 section 7.1, test 1
    test('matches the RFC 8032 test vector', () async {
      final AtTelemetryEd25519Signer signer =
          await AtTelemetryEd25519Signer.fromSeed(_hex(
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
      ));

      expect(
        signer.publicKey,
        _hex(
            'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'),
      );
      expect(
        await signer.sign(const <int>[]),
        _hex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
            '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'),
      );
    });

    test('verifies its own signature and nothing else', () async {
      final AtTelemetryEd25519Signer signer =
          await AtTelemetryEd25519Signer.generate();
      final List<int> message = utf8.encode('hello');
      final List<int> signature = await signer.sign(message);

      expect(
        await AtTelemetryEd25519Signer.verify(
          message: message,
          signature: signature,
          publicKey: signer.publicKey,
        ),
        isTrue,
      );
      expect(
        await AtTelemetryEd25519Signer.verify(
          message: utf8.encode('hellp'),
          signature: signature,
          publicKey: signer.publicKey,
        ),
        isFalse,
      );
      expect(
        await AtTelemetryEd25519Signer.verify(
          message: message,
          signature: signature.sublist(1),
          publicKey: signer.publicKey,
        ),
        isFalse,
      );
    });

    test('a seeded Random gives a repeatable key', () async {
      final AtTelemetryEd25519Signer first =
          await AtTelemetryEd25519Signer.generate(random: Random(3));
      final AtTelemetryEd25519Signer second =
          await AtTelemetryEd25519Signer.generate(random: Random(3));

      expect(first.seed, second.seed);
      expect(first.publicKey, second.publicKey);
      expect(first.seed, hasLength(AtTelemetryEd25519Signer.seedLength));
      expect(
        first.publicKey,
        hasLength(AtTelemetryEd25519Signer.publicKeyLength),
      );
    });

    test('is not affected by later changes to the seed it was given', () async {
      final List<int> seed = List<int>.filled(32, 1);
      final AtTelemetryEd25519Signer signer =
          await AtTelemetryEd25519Signer.fromSeed(seed);

      seed[0] = 2;

      expect(signer.seed.first, 1);
    });

    test('names its algorithm ed25519', () async {
      final AtTelemetryEd25519Signer signer =
          await AtTelemetryEd25519Signer.fromSeed(List<int>.filled(32, 0));

      expect(signer.algorithm, 'ed25519');
    });

    test('verify returns false for a public key of the wrong length', () async {
      final AtTelemetryEd25519Signer signer =
          await AtTelemetryEd25519Signer.fromSeed(List<int>.filled(32, 0));
      final List<int> message = utf8.encode('hello');
      final List<int> signature = await signer.sign(message);

      expect(
        await AtTelemetryEd25519Signer.verify(
          message: message,
          signature: signature,
          publicKey: signer.publicKey.sublist(1),
        ),
        isFalse,
      );
    });

    test('rejects a seed of the wrong length', () {
      expect(
        () => AtTelemetryEd25519Signer.fromSeed(List<int>.filled(33, 0)),
        throwsArgumentError,
      );
      expect(
        () => AtTelemetryEd25519Signer.fromSeed(List<int>.filled(31, 0)),
        throwsArgumentError,
      );
    });
  });
}

List<int> _hex(String hex) => <int>[
      for (int index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ];
