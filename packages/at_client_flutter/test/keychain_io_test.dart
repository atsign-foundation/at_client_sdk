import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_client_flutter/src/at_client_data.dart' show AtClientData;
import 'package:at_client_flutter/src/auth_constants.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_client_flutter/src/keychain/keychain_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'at_auth_service_test.dart';
import 'keychain_manager_test.dart';

void main(){

  late MockKeyChainStorage mockKeyChainStorage;
  late MockKeyChainManager mockKeyChainManager;

  setUp(() {
    mockKeyChainStorage = MockKeyChainStorage();
    mockKeyChainManager = MockKeyChainManager();
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
                "name": "@alice",
                "pkamPrivateKey": atKeys.apkamPrivateKey.toString(),
                "pkamPublicKey": atKeys.apkamPublicKey.toString(),
                "encryptionPublicKey": atKeys.defaultEncryptionPublicKey.toString(),
                "encryptionPrivateKey": atKeys.defaultEncryptionPrivateKey.toString(),
                "selfEncryptionKey": atKeys.defaultSelfEncryptionKey.toString(),
                "hiveSecret": null
              }
            ],
            "defaultAtsign": null
          })));

      keychainManager.keyChainStorage = mockKeyChainStorage;
      keychainAtKeysIo.keychainManager = keychainManager;
      Map<String, String> encryptedKeys = await keychainAtKeysIo.getEncryptedKeys('@alice');
      expect(encryptedKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE], atKeys.defaultSelfEncryptionKey);
      expect(encryptedKeys.containsKey(BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE), false);
      expect(encryptedKeys.containsKey(BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE), false);
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
              "encryptionPublicKey": atKeys.defaultEncryptionPublicKey.toString(),
              "encryptionPrivateKey": atKeys.defaultEncryptionPrivateKey.toString(),
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