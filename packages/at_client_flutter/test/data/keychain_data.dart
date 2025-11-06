import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_data.dart';
import 'package:at_commons/at_commons.dart';

final AtKeys dummyAtKeys = AtKeys()
  ..apkamPrivateKey = AtBytes.fromString('privateKey12')
  ..apkamPublicKey = AtBytes.fromString('publicKey123')
  ..defaultSelfEncryptionKey = AtBytes.fromString('selfEncKey12')
  ..defaultEncryptionPrivateKey = AtBytes.fromString('encPrivateKey123')
  ..defaultEncryptionPublicKey = AtBytes.fromString('encPublicKey')
  ..apkamSymmetricKey = AtBytes.fromString('apkamSymKey1')
  ..enrollmentId = 'enrollId1'
  ..metadata['hiveSecret'] = 'hiveSecret1'
  ..metadata['secret'] = 'secret1';

final String emptyAtKeysData = jsonEncode(AtKeysData().toJson());
final String dummyAtKeysData = jsonEncode(AtKeysData(
  keys: [
    dummyAtKeys,
  ],
  defaultAtsign: '@alice',
));

final String dummyEnrollmentData = jsonEncode(EnrollmentData(
  'enrollId1',
  dummyAtKeys,
  1625079600000000,
  namespace: {'namespace': 'namespace1'},
  keysFilePath: '/path/to/keysfile',
));

const legacyAtClientData = '''
    {
      "config": {
        "schemaVersion": 1,
        "useSharedAtSign": false
      },
      "keys": [
        {
          "name": "@alice",
          "aesPkamPrivateKey": "privateKey12",
          "aesPkamPublicKey": "publicKey123",
          "aesEncryptPublicKey": "encPublicKey",
          "aesEncryptPrivateKey": "encPrivateKey123",
          "selfEncryptionKey": "selfEncKey12",
          "apkamSymmetricKey": "apkamSymKey1",
          "enrollmentId": "enrollId1",
          "hiveSecret": "hiveSecret",
          "secret": "secret1"
        },
        {
          "name": "@bob",
          "aesPkamPrivateKey": "privateKey12",
          "aesPkamPublicKey": "publicKey123",
          "aesEncryptPublicKey": "encPublicKey",
          "aesEncryptPrivateKey": "encPrivateKey123",
          "selfEncryptionKey": "selfEncKey12",
          "apkamSymmetricKey": "apkamSymKey1",
          "enrollmentId": "enrollId2",
          "hiveSecret": "hiveSecret2",
          "secret": "secret2"
        }
      ],
      "defaultAtsign": "@alice"
    }
    ''';

const legacyEnrollmentInfo = '''
    {
      "enrollmentId": "enrollId1",
      "atAuthKeys": {
        "aesPkamPublicKey": "publicKey1",
        "aesPkamPrivateKey": "privateKey1",
        "aesEncryptPublicKey": "encPublicKey1",
        "aesEncryptPrivateKey": "encPrivateKey1",
        "selfEncryptionKey": "selfEncKey1",
        "apkamSymmetricKey": "apkamSymKey1",
        "enrollmentId": "enrollId1"
        },
      "enrollmentSubmissionTimeEpoch": 1625079600000000,
      "namespace": "namespace1",
      "keysFilePath": "/path/to/keysfile"
    }
    ''';
