import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_client_flutter/src/at_client_data.dart';
import 'package:mocktail/mocktail.dart';

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel('dev.fluttercommunity.plus/package_info'), (MethodCall methodCall) async {
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
      .setMockMethodCallHandler(MethodChannel('biometric_storage'), (MethodCall methodCall) async {
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
    late KeyChainStorage keyChainStorage;
    late MockBiometricStorage mockBiometricStorage;
    late MockBiometricStorageFile mockBiometricStorageFile;

    setUp(() {
      mockBiometricStorage = MockBiometricStorage();
      mockBiometricStorageFile = MockBiometricStorageFile();
      keyChainStorage = KeyChainStorage();
      keyChainStorage.biometricStorage = mockBiometricStorage;
    });

    test('readAtClientData returns AtClientData if data exists', () async {
      when(() => mockBiometricStorage.getStorage(any(), options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => '{"key": "value"}');

      final result = await keyChainStorage.readAtClientData();

      expect(result, isNotNull);
      expect(result?.toJson(), {'key': 'value'});
    });

    test('readAtClientData returns null if no data exists', () async {
      when(() => mockBiometricStorage.getStorage(any(), options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => null);

      final result = await keyChainStorage.readAtClientData();

      expect(result, isNull);
    });

    test('saveAtClientData saves data successfully', () async {
      final atClientData = AtClientData.fromJson({'key': 'value'});
      when(() => mockBiometricStorage.getStorage(any(), options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.write(any())).thenAnswer((_) async => Future.value());

      final result = await keyChainStorage.saveAtClientData(
        data: atClientData,
        useSharedStorage: false,
      );

      expect(result, isTrue);
      verify(() => mockBiometricStorageFile.write('{"key":"value"}')).called(1);
    });

    test('saveAtClientData returns false on failure', () async {
      final atClientData = AtClientData.fromJson({'key': 'value'});
      when(() => mockBiometricStorage.getStorage(any(), options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.write(any())).thenThrow(Exception());

      final result = await keyChainStorage.saveAtClientData(
        data: atClientData,
        useSharedStorage: false,
      );

      expect(result, isFalse);
    });

    test('deleteDataStore deletes data successfully', () async {
      when(() => mockBiometricStorage.getStorage(any(), options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.delete()).thenAnswer((_) async => Future.value());

      final result = await keyChainStorage.deleteDataStore();

      expect(result, isNull);
      verify(() => mockBiometricStorageFile.delete()).called(1);
    });

    test('readDataFromStore combines data on Windows platform', () async {
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => '2'); // Simulate 2 segments
      when(() => mockBiometricStorage.getStorage(any(), options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => 'segment1');

      final result = await keyChainStorage.readDataFromStore(
        store: mockBiometricStorageFile,
      );

      expect(result, 'segment1segment2');
    });

    // when(() => mockBiometricStorage.getStorage('${atSign}_enrollmentInfo', options: any(named: 'options')))
    //     .thenAnswer((_) async => mockBiometricStorageEnrollmentFile);

    // when(() => mockBiometricStorage.getStorage(any(that: startsWith('@atsigns')), options: any(named: 'options')))
    //     .thenAnswer(
    //   (_) async => mockBiometricStorageKeychainFile,
    // );

    // when(() => mockBiometricStorageKeychainFile.read())
    //     .thenAnswer((_) => Future.value(mockBiometricStorageKeychainFile.dummyStorageFile['${atSign}_enrollmentInfo']));

    // when(() => mockBiometricStorageKeychainFile.write(any(that: startsWith(''))))
    //     .thenAnswer((Invocation invocation) async {
    //   mockBiometricStorageKeychainFile.dummyStorageFile
    //       .putIfAbsent('${atSign}_enrollmentInfo_keychain', () => invocation.positionalArguments[0]);
    // });

    // when(() => mockBiometricStorageEnrollmentFile.read()).thenAnswer((_) async {
    //   String jsonEncodedEnrollmentInfo = await Future.value(jsonEncode(EnrollmentInfo(
    //       '010ad3dc-02ee-41c6-b74b-c82f5122b181',
    //       AtKeys()
    //         ..apkamPublicKey = AtBytes.fromString(pkamPublicKey)
    //         ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKey)
    //         ..defaultEncryptionPublicKey = AtBytes.fromString(encryptionPublicKey)
    //         ..apkamSymmetricKey = AtBytes.fromString(atChopsKeys.apkamSymmetricKey!.key)
    //         ..enrollmentId = '010ad3dc-02ee-41c6-b74b-c82f5122b181',
    //       DateTime.now().microsecondsSinceEpoch,
    //       {'wavi': 'rw'})));

    //   mockBiometricStorageEnrollmentFile.dummyStorageFile
    //       .putIfAbsent('${atSign}_enrollmentInfo', () => jsonEncodedEnrollmentInfo);

    //   return jsonEncodedEnrollmentInfo;
    // });

    // when(() => mockBiometricStorageEnrollmentFile.write(any(that: startsWith('{"enrollmentId"'))))
    //     .thenAnswer((Invocation invocation) async {
    //   mockBiometricStorageEnrollmentFile.dummyStorageFile.putIfAbsent(
    //       jsonEncode(
    //         EnrollmentInfo(
    //             '010ad3dc-02ee-41c6-b74b-c82f5122b181',
    //             AtKeys()
    //               ..apkamPublicKey = AtBytes.fromString(pkamPublicKey)
    //               ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKey)
    //               ..defaultEncryptionPublicKey = AtBytes.fromString(encryptionPublicKey)
    //               ..apkamSymmetricKey = AtBytes.fromString(atChopsKeys.apkamSymmetricKey!.key)
    //               ..enrollmentId = '010ad3dc-02ee-41c6-b74b-c82f5122b181',
    //             DateTime.now().microsecondsSinceEpoch,
    //             {'wavi': 'rw'}),
    //       ),
    //       () => invocation.positionalArguments[0]);
    // });
  });
}
