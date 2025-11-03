import 'package:at_auth/at_auth.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:mocktail/mocktail.dart';

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      }; // Mock successful authentication
    }
    return false;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel('biometric_storage'),
          (MethodCall methodCall) async {
    if (methodCall.method == 'init') {
      return {
        '''
        {
          'name': "dummy",
          'options': {
            'authenticationValidityDurationSeconds': -1,
            'authenticationRequired': false,
            'androidBiometricOnly': false,
            'darwinBiometricOnly': false,
          },
          'forceInit': forceInit,
        }
        '''
      };
    }
    return false;
  });
  group('KeyChainStorage Tests', () {
    late KeychainStorage keyChainStorage;
    late MockBiometricStorage mockBiometricStorage;
    late MockBiometricStorageFile mockBiometricStorageFile;

    setUp(() {
      mockBiometricStorage = MockBiometricStorage();
      mockBiometricStorageFile = MockBiometricStorageFile();
      keyChainStorage = KeychainStorage();
      keyChainStorage.biometricStorage = mockBiometricStorage;
    });

    test('readAtClientData returns AtClientData if data exists', () async {
      when(() => mockBiometricStorage.getStorage(any(),
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read())
          .thenAnswer((_) async => '{"key": "value"}');

      final result = await keyChainStorage.readAtKeysData();

      expect(result, isNotNull);
      expect(result?.toJson(),
          {'config': null, 'keys': [], 'defaultAtsign': null});
    });

    test('readAtClientData returns null if no data exists', () async {
      when(() => mockBiometricStorage.getStorage(any(),
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => null);

      final result = await keyChainStorage.readAtKeysData();

      expect(result, isNull);
    });

    test('saveAtClientData saves data successfully', () async {
      final atClientData = AtKeys.fromJson({'key': 'value'});
      when(() => mockBiometricStorage.getStorage(any(),
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.write(any()))
          .thenAnswer((_) async => Future.value());

      expect(
        () async =>
            await keyChainStorage.appendAtKeysToKeychain(keys: atClientData),
        returnsNormally,
      );
    });

    test('saveAtClientData returns false on failure', () async {
      final atKeys = AtKeys.fromJson({'key': 'value'});
      when(() => mockBiometricStorage.getStorage(any(),
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.write(any())).thenThrow(Exception());

      expect(
        () async => await keyChainStorage.appendAtKeysToKeychain(
          keys: atKeys,
        ),
        returnsNormally,
      );
    });

    test('deleteDataStore deletes data successfully', () async {
      when(() => mockBiometricStorage.getStorage(any(),
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.delete())
          .thenAnswer((_) async => Future.value());

      expect(
        () async => keyChainStorage.deleteAllAtKeysData(),
        returnsNormally,
      );
    });

    test('readDataFromStore combines data on Windows platform', () async {
      when(() => mockBiometricStorageFile.read())
          .thenAnswer((_) async => '2'); // Simulate 2 segments
      when(() => mockBiometricStorage.getStorage(any(),
              options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read())
          .thenAnswer((_) async => 'segment1');

      final result = await keyChainStorage.readAtKeysData();

      expect(result, 'segment1segment2');
    });
  });
}
