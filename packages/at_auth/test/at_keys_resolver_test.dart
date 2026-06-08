import 'dart:convert';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys_codec.dart';
import 'package:at_auth/src/keys/at_keys_models.dart';
import 'package:at_auth/src/keys/at_keys_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('AtKeysDocumentResolver.resolve', () {
    late AtKeysJsonCodec codec;
    late AtKeysDocumentResolver resolver;

    setUp(() {
      codec = AtKeysJsonCodec();
      resolver = AtKeysDocumentResolver();
    });

    test('resolves a valid document into paired and symmetric keys', () {
      final keys = resolver.resolve(codec.decodeDocument(_validDocument()));

      expect(keys.atSign, '@alice');
      expect(keys.asymmetricKeys, hasLength(2));
      expect(keys.symmetricKeys, hasLength(1));
      expect(keys.defaults[AtKeyPurpose.pkam], 'default-pkam');

      final pkam = keys.asymmetricKeys.singleWhere(
        (key) => key.pairId == 'default-pkam',
      );
      expect(pkam.purpose, AtKeyPurpose.pkam);
      expect(pkam.publicKey, 'cGthbS1wdWJsaWMta2V5');
      expect(pkam.privateKey, 'cGthbS1wcml2YXRlLWtleQ==');
      expect(pkam.operations, ['verify', 'authenticate', 'sign']);

      final encryption = keys.asymmetricKeys.singleWhere(
        (key) => key.pairId == 'default-encryption',
      );
      expect(encryption.privateKeyProtection?.keyRef, 'self-encryption');

      final selfEncryption = keys.symmetricKeys.single;
      expect(selfEncryption.id, 'self-encryption');
      expect(selfEncryption.purpose, AtKeyPurpose.selfEncryption);
    });

    test('throws when an asymmetric pair is incomplete', () {
      final json = _validDocument();
      final records = json['keys'] as List<dynamic>;
      records.removeWhere((record) => record['id'] == 'default-pkam-private');

      expect(
        () => resolver.resolve(codec.decodeDocument(json)),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws for duplicate pairId and kind', () {
      final json = _validDocument();
      final records = json['keys'] as List<dynamic>;
      records.add({
        ...Map<String, dynamic>.from(records[0] as Map<String, dynamic>),
        'id': 'duplicate-pkam-public',
      });

      expect(
        () => resolver.resolve(codec.decodeDocument(json)),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws when pair purposes disagree', () {
      final json = _validDocument();
      final records = json['keys'] as List<dynamic>;
      final pkamPrivate = records.singleWhere(
        (record) => record['id'] == 'default-pkam-private',
      );
      pkamPrivate['purpose'] = 'encryption';

      expect(
        () => resolver.resolve(codec.decodeDocument(json)),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws when pair fingerprints disagree', () {
      final json = _validDocument();
      final records = json['keys'] as List<dynamic>;
      final pkamPrivate = records.singleWhere(
        (record) => record['id'] == 'default-pkam-private',
      );
      pkamPrivate['fingerprint']['value'] = 'different-fingerprint';

      expect(
        () => resolver.resolve(codec.decodeDocument(json)),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws when an asymmetric default references a missing pairId', () {
      final json = _validDocument();
      final defaults = json['defaults'] as Map<String, dynamic>;
      defaults['pkam'] = 'missing-pkam';

      expect(
        () => resolver.resolve(codec.decodeDocument(json)),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws when a symmetric default references a missing id', () {
      final json = _validDocument();
      final defaults = json['defaults'] as Map<String, dynamic>;
      defaults['selfEncryption'] = 'missing-self-encryption';

      expect(
        () => resolver.resolve(codec.decodeDocument(json)),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('throws when a symmetric default references an asymmetric key', () {
      final json = _validDocument();
      final defaults = json['defaults'] as Map<String, dynamic>;
      defaults['selfEncryption'] = 'default-pkam-public';

      expect(
        () => resolver.resolve(codec.decodeDocument(json)),
        throwsA(isA<AtKeysValidationException>()),
      );
    });
  });
}

Map<String, dynamic> _validDocument() {
  return jsonDecode(jsonEncode({
    'version': 2,
    'atSign': '@alice',
    'documentNote': 'preserved',
    'keys': [
      {
        'id': 'default-pkam-public',
        'pairId': 'default-pkam',
        'purpose': 'pkam',
        'kind': 'public',
        'algorithm': 'rsa-2048',
        'fingerprint': {
          'algorithm': 'sha-256',
          'value': 'pkam-fingerprint',
        },
        'operations': ['verify'],
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
          'value': 'pkam-fingerprint',
        },
        'operations': ['authenticate', 'sign'],
        'recordNote': 'preserved',
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
          'value': 'encryption-fingerprint',
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
          'value': 'encryption-fingerprint',
        },
        'protection': {
          'type': 'encrypted',
          'keyRef': 'self-encryption',
          'algorithm': 'aes-256-ctr',
          'iv': 'AAAAAAAAAAAAAAAAAAAAAA==',
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
      'selfEncryption': 'self-encryption',
    },
  })) as Map<String, dynamic>;
}
