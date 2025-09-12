import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/src/keychain_io_impl.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:crypton/crypton.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'at_auth_service_test.dart';

class MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockPackageInfo extends Mock implements PackageInfo {}

class FakeStorageFileInitOptions extends Fake implements StorageFileInitOptions {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockBiometricStorageFile mockBiometricStorageFile;
  late MockBiometricStorage mockBiometricStorage;
  late MockKeychainAtKeysIo mockKeychainAtKeysIo;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel('dev.fluttercommunity.plus/package_info'), (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return {
        'appName': 'test',
        'packageName': 'test',
        'version': '1.0.0',
        'buildNumber': '1',
      };
    }
    return false;
  });

  setUp(() {
    registerFallbackValue(FakeStorageFileInitOptions());

    mockBiometricStorageFile = MockBiometricStorageFile();
    mockBiometricStorage = MockBiometricStorage();
    mockKeychainAtKeysIo = MockKeychainAtKeysIo();
  });

  group('A group of test getAtSign', () {
    test('A test to getAtSign when onboard disable shareAtSign', () async {
      var keychainManager = KeyChainManager();

      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer(
        (_) async => Future.value('''
            {
            "config" : {
                  "schemaVersion":1,
                  "useSharedAtsign":false
                  },
             "keys":[
                  {
                      "name":"@atSignTest",
                      "pkamPrivateKey":"",
                      "pkamPublicKey":"",
                      "encryptionPublicKey":"",
                      "encryptionPrivateKey":"",
                      "selfEncryptionKey":"",
                      "hiveSecret":null,
                      "secret":null
                  }
                ],
              "defaultAtsign":null}
            '''),
      );

      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Future.value(
          mockBiometricStorageFile,
        ),
      );

      keychainManager.biometricStorage = mockBiometricStorage;
      String? atSign = await keychainManager.getAtSign();
      expect(atSign, '@atSignTest');
    });

    test('A test to getAtSign when onboard enable shareAtSign', () async {
      var keychainManager = KeyChainManager();
      MockBiometricStorageFile mockBiometricShared = MockBiometricStorageFile();
      MockBiometricStorageFile mockBiometricDefault = MockBiometricStorageFile();

      when(
        () => mockBiometricShared.read(),
      ).thenAnswer(
        (_) async => Future.value('''
            {
              "config":null,
               "keys":[
                    {
                        "name":"@atSignTest",
                        "pkamPrivateKey":"",
                        "pkamPublicKey":"",
                        "encryptionPublicKey":"",
                        "encryptionPrivateKey":"",
                        "selfEncryptionKey":"",
                        "hiveSecret":null,
                        "secret":null
                    }
                  ],
               "defaultAtsign":null
            }
            '''),
      );

      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:shared',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Future.value(
          mockBiometricShared,
        ),
      );

      when(
        () => mockBiometricDefault.read(),
      ).thenAnswer(
        (_) async => Future.value(
            '{"config":{"schemaVersion":1,"useSharedAtsign":true},"keys":[],"defaultAtsign":"@atSignTest"}'),
      );

      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Future.value(
          mockBiometricDefault,
        ),
      );

      keychainManager.biometricStorage = mockBiometricStorage;

      String? atSign = await keychainManager.getAtSign();

      expect(atSign, '@atSignTest');
    });
  });

  group('A group of tests to assert backup of atKeys', () {
    // The test will assert backup of atKeys generated before the APKAM feature.
    test('A test to assert the legacy atKeys backup successfully', () async {
      var keychainManager = KeyChainManager();
      MockBiometricStorageFile mockBiometricDefault = MockBiometricStorageFile();
      KeychainAtKeysIo keychainAtKeysIo = KeychainAtKeysIo(keychainManager);
      AtKeys atKeys = keychainAtKeysIo.generateKeyPairs();

      when(
        () => mockBiometricDefault.read(),
      ).thenAnswer(
        (_) async => Future.value('''
        {"config":{"schemaVersion":1,"useSharedAtsign":false},
        "keys":[{"name":"@alice",
                 "pkamPrivateKey":"${atKeys.apkamPrivateKey.toString()}",
                 "pkamPublicKey":"${atKeys.apkamPublicKey.toString()}",
                 "encryptionPublicKey":"${atKeys.defaultEncryptionPublicKey.toString()}",
                 "encryptionPrivateKey":"${atKeys.defaultEncryptionPrivateKey.toString()}",
                 "selfEncryptionKey":"${atKeys.defaultSelfEncryptionKey.toString()}",
                 "hiveSecret":null,
                 "secret":null}],
                 "defaultAtsign":null}
        '''),
      );

      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Future.value(
          mockBiometricDefault,
        ),
      );

      keychainManager.biometricStorage = mockBiometricStorage;

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
      MockBiometricStorageFile mockBiometricDefault = MockBiometricStorageFile();
      KeychainAtKeysIo keychainAtKeysIo = KeychainAtKeysIo(keychainManager);
      AtKeys atKeys = keychainAtKeysIo.generateKeyPairs();

      when(
        () => mockBiometricDefault.read(),
      ).thenAnswer(
        (_) async => Future.value('''
        {"config":{"schemaVersion":1,"useSharedAtsign":false},
        "keys":[{"name":"@alice",
                 "pkamPrivateKey":"${atKeys.apkamPrivateKey.toString()}",
                 "pkamPublicKey":"${atKeys.apkamPublicKey.toString()}",
                 "encryptionPublicKey":"${atKeys.defaultEncryptionPublicKey.toString()}",
                 "encryptionPrivateKey":"${atKeys.defaultEncryptionPrivateKey.toString()}",
                 "selfEncryptionKey":"${atKeys.defaultSelfEncryptionKey.toString()}",
                 "apkamSymmetricKey":"${atKeys.apkamSymmetricKey.toString()}",
                 "enrollmentId":"123",
                 "hiveSecret":null,
                 "secret":null}],
                 "defaultAtsign":null}
        '''),
      );

      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Future.value(
          mockBiometricDefault,
        ),
      );

      keychainManager.biometricStorage = mockBiometricStorage;

      Map<String, String> encryptedKeys = await keychainAtKeysIo.getEncryptedKeys('@alice');
      expect(encryptedKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE]?.isNotEmpty, true);
      expect(encryptedKeys[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE], atKeys.defaultSelfEncryptionKey);
      expect(encryptedKeys[BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE], atKeys.apkamSymmetricKey);
      expect(encryptedKeys[BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE], '123');
    });
  });
}
