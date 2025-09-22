import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_client_flutter/src/at_client_data.dart' show AtClientData;
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MockPackageInfo extends Mock implements PackageInfo {}

class MockKeyChainStorage extends Mock implements KeyChainStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockKeyChainStorage mockKeyChainStorage;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          MethodChannel('dev.fluttercommunity.plus/package_info'),
          (MethodCall methodCall) async {
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
    mockKeyChainStorage = MockKeyChainStorage();
  });

  group('A group of test getAtSign', () {
    test('A test to getAtSign when onboard disable shareAtSign', () async {
      var keychainManager = KeyChainManager();

      when(
        () => mockKeyChainStorage.readAtClientData(),
      ).thenAnswer(
        (_) async => Future.value(AtClientData.fromJson({
          "config": {"schemaVersion": 1, "useSharedAtsign": false},
          "keys": [
            {
              "atsign": "@atSignTest",
              auth_constants.apkamPrivateKey: "",
              auth_constants.apkamPublicKey: "",
              auth_constants.defaultEncryptionPublicKey: "",
              auth_constants.defaultEncryptionPrivateKey: "",
              auth_constants.defaultSelfEncryptionKey: "",
              "hiveSecret": null,
            }
          ],
          "defaultAtsign": null
        })),
      );

      keychainManager.keyChainStorage = mockKeyChainStorage;
      String? atSign = await keychainManager.getDefaultAtSign();
      expect(atSign, '@atSignTest');
    });

    test('A test to getAtSign when onboard enable shareAtSign', () async {
      var keychainManager = KeyChainManager();

      when(
        () => mockKeyChainStorage.readAtClientData(useSharedStorage: false),
      ).thenAnswer((_) async => Future.value(AtClientData.fromJson({
            "config": null,
            "keys": [
              {
                "atsign": "@atSignTest",
                auth_constants.apkamPrivateKey: "",
                auth_constants.apkamPublicKey: "",
                auth_constants.defaultEncryptionPublicKey: "",
                auth_constants.defaultEncryptionPrivateKey: "",
                auth_constants.defaultSelfEncryptionKey: "",
                "hiveSecret": null,
                "secret": null
              }
            ],
            "defaultAtsign": null
          })));

      when(
        () => mockKeyChainStorage.readAtClientData(useSharedStorage: true),
      ).thenAnswer((_) async => Future.value(AtClientData.fromJson({
            "config": {"schemaVersion": 1, "useSharedAtsign": true},
            "keys": [],
            "defaultAtsign": "@atSignTest"
          })));

      keychainManager.keyChainStorage = mockKeyChainStorage;
      String? atSign = await keychainManager.getDefaultAtSign();

      expect(atSign, '@atSignTest');
    });
  });
}
