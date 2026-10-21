import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_data.dart';

final AtKeys dummyAtKeys =
    AtKeys.legacy(
        apkamPrivateKey: 'privateKey12',
        apkamPublicKey: 'publicKey123',
        selfEncryptionKey: 'selfEncKey12',
        encryptionPrivateKey: 'encPrivateKey123',
        encryptionPublicKey: 'encPublicKey',
        apkamSymmetricKey: 'apkamSymKey1',
        enrollmentId: 'enrollId1',
      )
      ..metadata['hiveSecret'] = 'hiveSecret1'
      ..metadata['secret'] = 'secret1';

final String emptyAtKeysData = jsonEncode(AtKeysData().toJson());
final String dummyAtKeysData = jsonEncode(
  AtKeysData(keys: [dummyAtKeys], defaultAtsign: '@alice'),
);

/// at_client_mobile's keychain document (`AtClientData` holding `AtsignKey`s)
/// exactly as it writes it to `@atsigns:<package>` (checked against 3.2.0
/// through 3.3.1).
///
/// Frozen: devices onboarded by an app built on at_client_mobile hold this
/// shape, so its field names must not be edited to match the reader.
const legacyAtClientData = '''
    {
      "config": {
        "schemaVersion": 1,
        "useSharedAtsign": false
      },
      "keys": [
        {
          "name": "@alice",
          "pkamPrivateKey": "privateKey12",
          "pkamPublicKey": "publicKey123",
          "encryptionPublicKey": "encPublicKey",
          "encryptionPrivateKey": "encPrivateKey123",
          "selfEncryptionKey": "selfEncKey12",
          "apkamSymmetricKey": "apkamSymKey1",
          "enrollmentId": "enrollId1",
          "hiveSecret": "hiveSecret",
          "secret": "secret1"
        },
        {
          "name": "@bob",
          "pkamPrivateKey": "privateKey12",
          "pkamPublicKey": "publicKey123",
          "encryptionPublicKey": "encPublicKey",
          "encryptionPrivateKey": "encPrivateKey123",
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
