import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

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
}