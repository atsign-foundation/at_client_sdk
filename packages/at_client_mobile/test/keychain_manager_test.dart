import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';

class MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockPackageInfo extends Mock implements PackageInfo {}

class FakeStorageFileInitOptions extends Fake
    implements StorageFileInitOptions {}

void main() {
  late MockBiometricStorageFile mockBiometricStorageFile;
  late MockBiometricStorage mockBiometricStorage;

  setUp(() {
    registerFallbackValue(FakeStorageFileInitOptions());

    mockBiometricStorageFile = MockBiometricStorageFile();
    mockBiometricStorage = MockBiometricStorage();
  });

  group('A group of test getAtSign', () {
    test('A test to getAtSign when onboard disable shareAtSign', () async {
      var keychainManager = KeyChainManager.getInstance();

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
          '@atsigns:',
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
      var keychainManager = KeyChainManager.getInstance();
      MockBiometricStorageFile mockBiometricShared = MockBiometricStorageFile();
      MockBiometricStorageFile mockBiometricDefault =
          MockBiometricStorageFile();

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
      var keychainManager = KeyChainManager.getInstance();
      MockBiometricStorageFile mockBiometricDefault =
          MockBiometricStorageFile();

      RSAKeypair pkamkeyPair = KeyChainManager.getInstance().generateKeyPair();
      RSAKeypair encryptionKeyPair =
          KeyChainManager.getInstance().generateKeyPair();
      String selfEncryptionKey = KeyChainManager.getInstance().generateAESKey();

      when(
        () => mockBiometricDefault.read(),
      ).thenAnswer(
        (_) async => Future.value('''
        {"config":{"schemaVersion":1,"useSharedAtsign":false},
        "keys":[{"name":"@alice",
                 "pkamPrivateKey":"${pkamkeyPair.privateKey.toString()}",
                 "pkamPublicKey":"${pkamkeyPair.publicKey.toString()}",
                 "encryptionPublicKey":"${encryptionKeyPair.publicKey.toString()}",
                 "encryptionPrivateKey":"${encryptionKeyPair.privateKey.toString()}",
                 "selfEncryptionKey":"$selfEncryptionKey",
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

      Map<String, String> encryptedKeys =
          await keychainManager.getEncryptedKeys('@alice');
      expect(
          encryptedKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE]
              ?.isNotEmpty,
          true);
      expect(
          encryptedKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE]
              ?.isNotEmpty,
          true);
      expect(
          encryptedKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE]
              ?.isNotEmpty,
          true);
      expect(
          encryptedKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE]
              ?.isNotEmpty,
          true);
      expect(encryptedKeys[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE],
          selfEncryptionKey);
      expect(
          encryptedKeys
              .containsKey(BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE),
          false);
      expect(
          encryptedKeys
              .containsKey(BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE),
          false);
    });

    test('A test to assert atKeys file contains apkam keys', () async {
      var keychainManager = KeyChainManager.getInstance();
      MockBiometricStorageFile mockBiometricDefault =
          MockBiometricStorageFile();

      RSAKeypair pkamkeyPair = KeyChainManager.getInstance().generateKeyPair();
      RSAKeypair encryptionKeyPair =
          KeyChainManager.getInstance().generateKeyPair();
      String selfEncryptionKey = KeyChainManager.getInstance().generateAESKey();
      String apkamEncryptionKey =
          KeyChainManager.getInstance().generateAESKey();

      when(
        () => mockBiometricDefault.read(),
      ).thenAnswer(
        (_) async => Future.value('''
        {"config":{"schemaVersion":1,"useSharedAtsign":false},
        "keys":[{"name":"@alice",
                 "pkamPrivateKey":"${pkamkeyPair.privateKey.toString()}",
                 "pkamPublicKey":"${pkamkeyPair.publicKey.toString()}",
                 "encryptionPublicKey":"${encryptionKeyPair.publicKey.toString()}",
                 "encryptionPrivateKey":"${encryptionKeyPair.privateKey.toString()}",
                 "selfEncryptionKey":"$selfEncryptionKey",
                 "apkamSymmetricKey":"$apkamEncryptionKey",
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

      Map<String, String> encryptedKeys =
          await keychainManager.getEncryptedKeys('@alice');
      expect(
          encryptedKeys[BackupKeyConstants.PKAM_PUBLIC_KEY_FROM_KEY_FILE]
              ?.isNotEmpty,
          true);
      expect(
          encryptedKeys[BackupKeyConstants.PKAM_PRIVATE_KEY_FROM_KEY_FILE]
              ?.isNotEmpty,
          true);
      expect(
          encryptedKeys[BackupKeyConstants.ENCRYPTION_PUBLIC_KEY_FROM_FILE]
              ?.isNotEmpty,
          true);
      expect(
          encryptedKeys[BackupKeyConstants.ENCRYPTION_PRIVATE_KEY_FROM_FILE]
              ?.isNotEmpty,
          true);
      expect(encryptedKeys[BackupKeyConstants.SELF_ENCRYPTION_KEY_FROM_FILE],
          selfEncryptionKey);
      expect(encryptedKeys[BackupKeyConstants.APKAM_SYMMETRIC_KEY_FROM_FILE],
          apkamEncryptionKey);
      expect(encryptedKeys[BackupKeyConstants.APKAM_ENROLLMENT_ID_FROM_FILE],
          '123');
    });
  });
}
