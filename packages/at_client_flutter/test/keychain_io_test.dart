import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_client_flutter/src/at_client_data.dart' show AtClientData;
import 'package:at_client_flutter/src/auth_constants.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/keychain/keychain_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'at_auth_service_test.dart';
import 'keychain_manager_test.dart';

void main() {
  late MockKeyChainStorage mockKeyChainStorage;
  late MockKeyChainManager mockKeyChainManager;

  setUp(() {
    mockKeyChainStorage = MockKeyChainStorage();
    mockKeyChainManager = MockKeyChainManager();
    mockKeyChainManager.keyChainStorage = mockKeyChainStorage;
  });

  group('A group of tests to assert backup of atKeys', () {
    // The test will assert backup of atKeys generated before the APKAM feature.
    test('A test to assert the legacy atKeys backup successfully', () async {
      var keychainManager = KeyChainManager();
      KeychainAtKeysIo keychainAtKeysIo = KeychainAtKeysIo();
      AtKeys atKeys = keychainAtKeysIo.generateKeyPairs();

      when(
        () => mockKeyChainStorage.readAtClientData(),
      ).thenAnswer((_) async => Future.value(AtClientData.fromJson({
            "config": {"schemaVersion": 1, "useSharedAtsign": false},
            "keys": [
              {
                "atsign": "@alice",
                auth_constants.apkamPrivateKey:
                    atKeys.apkamPrivateKey.toString(),
                auth_constants.apkamPublicKey: atKeys.apkamPublicKey.toString(),
                auth_constants.defaultEncryptionPublicKey:
                    atKeys.defaultEncryptionPublicKey.toString(),
                auth_constants.defaultEncryptionPrivateKey:
                    atKeys.defaultEncryptionPrivateKey.toString(),
                auth_constants.defaultSelfEncryptionKey:
                    atKeys.defaultSelfEncryptionKey.toString(),
                "hiveSecret": null
              }
            ],
            "defaultAtsign": null
          })));

      keychainManager.keyChainStorage = mockKeyChainStorage;
      keychainAtKeysIo.keychainManager = keychainManager;
      Map<String, String> encryptedKeys =
          await keychainAtKeysIo.getEncryptedKeys('@alice');
      expect(encryptedKeys[auth_constants.apkamPublicKey]?.isNotEmpty, true);
      expect(encryptedKeys[auth_constants.apkamPrivateKey]?.isNotEmpty, true);
      expect(
          encryptedKeys[auth_constants.defaultEncryptionPublicKey]?.isNotEmpty,
          true);
      expect(
          encryptedKeys[auth_constants.defaultEncryptionPrivateKey]?.isNotEmpty,
          true);
      expect(encryptedKeys[auth_constants.defaultSelfEncryptionKey],
          atKeys.defaultSelfEncryptionKey.toString());
      expect(
          encryptedKeys.containsKey(auth_constants.apkamSymmetricKey), false);
      expect(
          encryptedKeys.containsKey(auth_constants.apkamEnrollmentId), false);
    });

    test('A test to assert atKeys file contains apkam keys', () async {
      var keychainManager = KeyChainManager();
      KeychainAtKeysIo keychainAtKeysIo = KeychainAtKeysIo();
      AtKeys atKeys = keychainAtKeysIo.generateKeyPairs();

      when(
        () => mockKeyChainStorage.readAtClientData(),
      ).thenAnswer(
        (_) async => Future.value(AtClientData.fromJson({
          "config": {"schemaVersion": 1, "useSharedAtsign": false},
          "keys": [
            {
              "name": "@alice",
              "pkamPrivateKey": atKeys.apkamPrivateKey.toString(),
              "pkamPublicKey": atKeys.apkamPublicKey.toString(),
              "encryptionPublicKey":
                  atKeys.defaultEncryptionPublicKey.toString(),
              "encryptionPrivateKey":
                  atKeys.defaultEncryptionPrivateKey.toString(),
              "selfEncryptionKey": atKeys.defaultSelfEncryptionKey.toString(),
              "apkamSymmetricKey": atKeys.apkamSymmetricKey.toString(),
              "enrollmentId": "123",
              "hiveSecret": null,
              "secret": null
            }
          ],
          "defaultAtsign": null
        })),
      );
    });
  });
}
