import 'dart:convert';
import 'dart:io';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/at_keys_io.dart';
import 'package:at_auth/src/keys/at_keys_models.dart';
import 'package:at_auth/src/keys/legacy/legacy_at_keys_util.dart';
import 'package:at_auth/src/keys/versioned_file_at_keys_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('VersionedFileAtKeysIo', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'versioned_file_at_keys_io_test_',
      );
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('reads a versioned atKeys file into AtKeysSet', () async {
      await writeJson(tempDirectory, '@alice', _validDocument('@alice'));
      final reader = readerFor(tempDirectory);

      final keys = await reader.read('@alice');

      expect(keys.atSign, '@alice');
      expect(keys.asymmetricKeys, hasLength(2));
      expect(keys.symmetricKeys.single.purpose, KeyPurpose.selfEncryption);
    });

    test('throws when requested atSign differs from document atSign', () async {
      await writeJson(tempDirectory, '@alice', _validDocument('@bob'));
      final reader = readerFor(tempDirectory);

      await expectLater(
        () => reader.read('@alice'),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('routes legacy fixed-field files into AtKeysSet', () async {
      await writeLegacyAtKeys(tempDirectory, '@alice', _legacyAtKeys());
      final reader = readerFor(tempDirectory);

      final keys = await reader.read('@alice');

      expect(keys.enrollmentId, 'legacy-enrollment');
      expect(keys.defaults[KeyPurpose.pkam], 'legacy-pkam');
      expect(
        keys.asymmetricKeys
            .singleWhere(
              (key) => key.pairId == 'legacy-pkam',
            )
            .privateKey,
        AtBytes.fromString('cGthbS1wcml2YXRlLWtleQ=='),
      );
      expect(keys.symmetricKeys, hasLength(2));
    });

    test('rejects legacy fixed-field files when legacy is not allowed',
        () async {
      await writeLegacyAtKeys(tempDirectory, '@alice', _legacyAtKeys());
      final reader = readerFor(tempDirectory);

      await expectLater(
        () => reader.read(
          '@alice',
          options: const AtKeysReadOptions(allowLegacy: false),
        ),
        throwsA(isA<AtKeysValidationException>()),
      );
    });

    test('reads passphrase-protected versioned atKeys files', () async {
      await writeEncryptedJson(
        tempDirectory,
        '@alice',
        _validDocument('@alice'),
        passPhrase: 'qwerty',
      );
      final reader = readerFor(tempDirectory, passPhrase: 'qwerty');

      final keys = await reader.read('@alice');

      expect(keys.atSign, '@alice');
      expect(keys.defaults[KeyPurpose.encryption], 'default-encryption');
    });

    test('routes passphrase-protected legacy files into AtKeysSet', () async {
      await writeLegacyAtKeys(
        tempDirectory,
        '@alice',
        _legacyAtKeys(),
        passPhrase: 'qwerty',
      );
      final reader = readerFor(tempDirectory, passPhrase: 'qwerty');

      final keys = await reader.read('@alice');

      expect(keys.enrollmentId, 'legacy-enrollment');
      expect(keys.defaults[KeyPurpose.pkam], 'legacy-pkam');
      expect(keys.symmetricKeys, hasLength(2));
    });

    test('requires passphrase for passphrase envelopes', () async {
      await writeJson(tempDirectory, '@alice', {
        'content': 'ZW5jcnlwdGVkLWRvY3VtZW50',
        'iv': 'AAAAAAAAAAAAAAAAAAAAAA==',
        'hashingAlgoType': 'argon2id',
      });
      final reader = readerFor(tempDirectory);

      await expectLater(
        () => reader.read('@alice'),
        throwsA(isA<AtKeysDecryptionException>()),
      );
    });
  });
}

VersionedFileAtKeysIo readerFor(
  Directory tempDirectory, {
  String? passPhrase,
}) {
  return VersionedFileAtKeysIo(
    filePath: (atSign) => filePathFor(tempDirectory, atSign),
    passPhrase: passPhrase,
  );
}

Future<void> writeJson(
  Directory tempDirectory,
  String atSign,
  Map<String, dynamic> json,
) async {
  final file = File(filePathFor(tempDirectory, atSign));
  await file.writeAsString(jsonEncode(json));
}

Future<void> writeLegacyAtKeys(
  Directory tempDirectory,
  String atSign,
  AtKeys atKeys, {
  String? passPhrase,
}) async {
  var atKeysData = await LegacyKeyIOUtil.encryptAtKeysWithSelfEncKey(
    atKeys,
    PkamAuthMode.keysFile,
    atSign,
  );
  if (passPhrase != null) {
    atKeysData =
        (await AtKeysCrypto.fromHashingAlgorithm(HashingAlgoType.argon2id)
                .encrypt(atKeysData, passPhrase))
            .toString();
  }
  final file = File(filePathFor(tempDirectory, atSign));
  await file.writeAsString(atKeysData);
}

Future<void> writeEncryptedJson(
  Directory tempDirectory,
  String atSign,
  Map<String, dynamic> json, {
  required String passPhrase,
}) async {
  final atEncrypted =
      await AtKeysCrypto.fromHashingAlgorithm(HashingAlgoType.argon2id).encrypt(
    jsonEncode(json),
    passPhrase,
  );
  final file = File(filePathFor(tempDirectory, atSign));
  await file.writeAsString(atEncrypted.toString());
}

String filePathFor(Directory tempDirectory, String atSign) {
  return '${tempDirectory.path}/$atSign.atKeys';
}

AtKeys _legacyAtKeys() {
  return AtKeys()
    ..apkamPublicKey = AtBytes.fromString('cGthbS1wdWJsaWMta2V5')
    ..apkamPrivateKey = AtBytes.fromString('cGthbS1wcml2YXRlLWtleQ==')
    ..defaultEncryptionPublicKey =
        AtBytes.fromString('ZW5jcnlwdGlvbi1wdWJsaWMta2V5')
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString('ZW5jcnlwdGlvbi1wcml2YXRlLWtleQ==')
    ..defaultSelfEncryptionKey =
        AtBytes.fromString(base64Encode(List<int>.filled(32, 1)))
    ..apkamSymmetricKey =
        AtBytes.fromString(base64Encode(List<int>.filled(32, 2)))
    ..enrollmentId = 'legacy-enrollment';
}

Map<String, dynamic> _validDocument(String atSign) {
  return {
    'version': 2,
    'atSign': atSign,
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
      'selfEncryption': 'self-encryption',
    },
  };
}
