import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_codec.dart';
import 'package:at_auth/src/keys/at_keys_document.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysJsonCodec.decodeDocument', () {
    late AtKeysJsonCodec codec;

    setUp(() {
      codec = AtKeysJsonCodec();
    });

    test('decodes a valid versioned document', () {
      final document = codec.decodeDocument(_validDocument());

      expect(document.version, 2);
      expect(document.atsign, '@alice');
      expect(document.keys, hasLength(5));
      expect(document.defaults[KeyPurposes.pkam], 'default-pkam');
      expect(document.defaults[KeyPurposes.selfEncryption], 'self-encryption');

      final pkamPrivate = document.keys.singleWhere(
        (record) => record.id == 'default-pkam-private',
      );
      expect(pkamPrivate.purpose, KeyPurposes.pkam);
      expect(pkamPrivate.kind, KeyRecordKind.private);
      expect(pkamPrivate.operations, ['authenticate', 'sign']);
    });

    test('encodes a decoded document with stable JSON tokens', () {
      final document = codec.decodeDocument(_validDocument());
      final encoded = codec.encodeDocument(document);

      expect(encoded['version'], 2);
      expect(encoded['defaults']['self-encryption'], 'self-encryption');

      final encodedKeys = encoded['keys'] as List<dynamic>;
      final selfEncryption = encodedKeys.singleWhere(
        (record) => record['id'] == 'self-encryption',
      );
      expect(selfEncryption['purpose'], 'self-encryption');
      expect(selfEncryption['kind'], 'symmetric');
    });

    test('throws for unsupported version', () {
      final json = _validDocument()..['version'] = 3;

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysUnsupportedVersionException>()),
      );
    });

    test('throws for missing defaults object', () {
      final json = _validDocument()..remove('defaults');

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysParseException>()),
      );
    });

    test('throws for duplicate record ids', () {
      final json = _validDocument();
      final keys = json['keys'] as List<dynamic>;
      keys[1]['id'] = keys[0]['id'];

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws for malformed base64 value', () {
      final json = _validDocument();
      final keys = json['keys'] as List<dynamic>;
      keys[0]['value'] = 'not base64';

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws for unsupported key material algorithm', () {
      final json = _validDocument();
      final keys = json['keys'] as List<dynamic>;
      keys[0]['algorithm'] = 'rsa-internal-name';

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysUnsupportedAlgorithmException>()),
      );
    });

    test('leaves asymmetric pair completeness to the resolver', () {
      final json = _validDocument();
      final keys = json['keys'] as List<dynamic>;
      keys.removeWhere((record) => record['id'] == 'default-pkam-private');

      final document = codec.decodeDocument(json);

      expect(document.keys, hasLength(4));
    });

    test('throws when a symmetric key has pairId', () {
      final json = _validDocument();
      final keys = json['keys'] as List<dynamic>;
      final selfEncryption = keys.singleWhere(
        (record) => record['id'] == 'self-encryption',
      );
      selfEncryption['pairId'] = 'not-valid-for-symmetric';

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws when protection references a missing key', () {
      final json = _validDocument();
      final keys = json['keys'] as List<dynamic>;
      final encryptionPrivate = keys.singleWhere(
        (record) => record['id'] == 'default-encryption-private',
      );
      encryptionPrivate['protection'] = {
        'type': 'encrypted',
        'keyRef': 'missing-key',
        'algorithm': 'aes-256-ctr',
        'iv': 'AAAAAAAAAAAAAAAAAAAAAA==',
      };

      expect(
        () => codec.decodeDocument(json),
        throwsA(isA<AtKeysProtectionException>()),
      );
    });
  });
}

Map<String, dynamic> _validDocument() {
  return jsonDecode(jsonEncode({
    'version': 2,
    'atSign': '@alice',
    'keys': [
      {
        'id': 'default-pkam-public',
        'pairId': 'default-pkam',
        'purpose': 'pkam',
        'kind': 'public',
        'algorithm': 'rsa-2048',
        'fingerprint': {
          'algorithm': 'sha-256',
          'value': base64Encode(utf8.encode('pkam-fingerprint')),
        },
        'value': 'cGthbS1wdWJsaWMta2V5',
      },
      {
        'id': 'default-pkam-private',
        'pairId': 'default-pkam',
        'purpose': 'pkam',
        'kind': 'private',
        'algorithm': 'rsa-2048',
        'fingerprint': {
          'algorithm': 'sha-256',
          'value': base64Encode(utf8.encode('pkam-fingerprint')),
        },
        'operations': ['authenticate', 'sign'],
        'value': 'cGthbS1wcml2YXRlLWtleQ==',
      },
      {
        'id': 'default-encryption-public',
        'pairId': 'default-encryption',
        'purpose': 'encryption',
        'kind': 'public',
        'algorithm': 'rsa-2048',
        'fingerprint': {
          'algorithm': 'sha-256',
          'value': base64Encode(utf8.encode('encryption-fingerprint')),
        },
        'value': 'ZW5jcnlwdGlvbi1wdWJsaWMta2V5',
      },
      {
        'id': 'default-encryption-private',
        'pairId': 'default-encryption',
        'purpose': 'encryption',
        'kind': 'private',
        'algorithm': 'rsa-2048',
        'fingerprint': {
          'algorithm': 'sha-256',
          'value': base64Encode(utf8.encode('encryption-fingerprint')),
        },
        'value': 'ZW5jcnlwdGlvbi1wcml2YXRlLWtleQ==',
      },
      {
        'id': 'self-encryption',
        'purpose': 'self-encryption',
        'kind': 'symmetric',
        'algorithm': 'aes-256',
        'value': 'c2VsZi1lbmNyeXB0aW9uLWtleQ==',
      },
    ],
    'defaults': {
      'pkam': 'default-pkam',
      'encryption': 'default-encryption',
      'self-encryption': 'self-encryption',
    },
  })) as Map<String, dynamic>;
}
