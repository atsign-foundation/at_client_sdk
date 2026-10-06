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

    test('rejects a seed of the wrong length', () {
      expect(
        () => AtTelemetryEd25519Signer.fromSeed(List<int>.filled(31, 0)),
        throwsArgumentError,
      );
    });
  });

  group('AtTelemetryPublicKeyRecord', () {
    late AtTelemetryEd25519Signer signer;

    setUpAll(() async {
      signer = await AtTelemetryEd25519Signer.fromSeed(
        List<int>.generate(32, (int index) => index),
      );
    });

    test('round trips through its JSON value', () {
      final AtTelemetryPublicKeyRecord record = AtTelemetryPublicKeyRecord(
        algorithm: 'ed25519',
        publicKey: signer.publicKey,
      );
      final AtTelemetryPublicKeyRecord parsed =
          AtTelemetryPublicKeyRecord.parse(record.encode());

      expect(jsonDecode(record.encode()), <String, Object?>{
        'keyId': record.keyId,
        'alg': 'ed25519',
        'publicKey': base64Encode(signer.publicKey),
      });
      expect(parsed.keyId, record.keyId);
      expect(parsed.algorithm, 'ed25519');
      expect(parsed.publicKey, signer.publicKey);
    });

    test('the key id is 16 base64url characters of the key\'s hash', () {
      final String keyId =
          AtTelemetryPublicKeyRecord.keyIdFor(signer.publicKey);

      expect(keyId, matches(AtTelemetryPublicKeyRecord.keyIdPattern));
      expect(keyId, isNot(AtTelemetryPublicKeyRecord.keyIdFor(<int>[1])));
    });

    test('rejects a record whose key id names another key', () {
      final String value = jsonEncode(<String, String>{
        'keyId': AtTelemetryPublicKeyRecord.keyIdFor(<int>[1]),
        'alg': 'ed25519',
        'publicKey': base64Encode(signer.publicKey),
      });

      expect(
          () => AtTelemetryPublicKeyRecord.parse(value), throwsFormatException);
    });

    final Map<String, String> invalid = <String, String>{
      'not JSON': 'nope',
      'not an object': '[]',
      'missing fields': '{"keyId":"x"}',
      'an unknown alg': jsonEncode(<String, String>{
        'keyId': 'AAAAAAAAAAAAAAAA',
        'alg': 'rsa2048',
        'publicKey': base64Encode(List<int>.filled(32, 1)),
      }),
      'a short key': jsonEncode(<String, String>{
        'keyId': AtTelemetryPublicKeyRecord.keyIdFor(<int>[1, 2]),
        'alg': 'ed25519',
        'publicKey': base64Encode(<int>[1, 2]),
      }),
    };
    for (final MapEntry<String, String> entry in invalid.entries) {
      test('rejects ${entry.key}', () {
        expect(() => AtTelemetryPublicKeyRecord.parse(entry.value),
            throwsFormatException);
      });
    }
  });

  group('AtTelemetrySequence', () {
    test('round trips through its header', () {
      final AtTelemetrySequence sequence = AtTelemetrySequence(
        bootId: AtTelemetrySequence.newBootId(random: Random(1)),
        number: 7,
      );

      expect(AtTelemetrySequence.parse(sequence.header), sequence);
      expect(sequence.header, matches(r'^boot=[A-Za-z0-9_-]{22};seq=7$'));
    });

    test('a new boot id is 16 random bytes', () {
      final String bootId = AtTelemetrySequence.newBootId();

      expect(base64Url.decode('$bootId=='), hasLength(16));
      expect(bootId, isNot(AtTelemetrySequence.newBootId()));
    });

    test('rejects a negative or oversized number', () {
      expect(
        () => AtTelemetrySequence(
          bootId: 'AAECAwQFBgcICQoLDA0ODw',
          number: -1,
        ),
        throwsRangeError,
      );
      expect(
        () => AtTelemetrySequence.parse(
          'boot=AAECAwQFBgcICQoLDA0ODw;seq=9007199254740992',
        ),
        throwsFormatException,
      );
    });

    test('rejects a malformed boot id', () {
      expect(
        () => AtTelemetrySequence.parse('boot=short;seq=1'),
        throwsFormatException,
      );
    });
  });
}

List<int> _hex(String hex) => <int>[
      for (int index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ];
