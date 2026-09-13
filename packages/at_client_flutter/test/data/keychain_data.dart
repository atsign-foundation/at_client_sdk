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
final String dummyAtKeysData = jsonEncode(
  AtKeysData(keys: [dummyAtKeys], defaultAtsign: '@alice'),
);

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

bool checkSchemaEquality(KeychainData keychainData) {
  Map<String, dynamic> jsonData = {};
  if (keychainData is AtKeysData) {
    jsonData = jsonDecode(dummyAtKeysData);
  }
  final keychainDataJson = keychainData.toJson();
  if (keychainDataJson.length != jsonData.length) {
    return false;
  }
  for (final key in keychainDataJson.keys) {
    if (!jsonData.containsKey(key)) {
      return false;
    }
  }
  return true;
}
