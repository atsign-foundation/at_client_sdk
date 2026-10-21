import 'dart:convert';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

void main() {
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

    test('the constructor rejects an unknown alg or a short key', () {
      expect(
        () => AtTelemetryPublicKeyRecord(
          algorithm: 'rsa2048',
          publicKey: signer.publicKey,
        ),
        throwsArgumentError,
      );
      expect(
        () => AtTelemetryPublicKeyRecord(
          algorithm: 'ed25519',
          publicKey: signer.publicKey.sublist(1),
        ),
        throwsArgumentError,
      );
    });

    test('is not affected by later changes to the key it was given', () {
      final List<int> publicKey = List<int>.of(signer.publicKey);
      final AtTelemetryPublicKeyRecord record = AtTelemetryPublicKeyRecord(
        algorithm: 'ed25519',
        publicKey: publicKey,
      );

      publicKey[0] ^= 0xff;

      expect(record.publicKey, signer.publicKey);
      expect(
          record.keyId, AtTelemetryPublicKeyRecord.keyIdFor(signer.publicKey));
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
      'a key that is not base64': jsonEncode(<String, String>{
        'keyId': 'AAAAAAAAAAAAAAAA',
        'alg': 'ed25519',
        'publicKey': '!!!',
      }),
      'non-string fields': '{"keyId":1,"alg":"ed25519","publicKey":"x"}',
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
}
