import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:at_client_flutter/src/at_client_data.dart';
import 'package:mocktail/mocktail.dart';

class MockBiometricStorage extends Mock implements BiometricStorage {}

class MockBiometricStorageFile extends Mock implements BiometricStorageFile {}

void main() {
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
      when(() => mockBiometricStorageFile.read())
          .thenAnswer((_) async => '{"key": "value"}');

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
      when(() => mockBiometricStorageFile.delete())
          .thenAnswer((_) async => Future.value());

      final result = await keyChainStorage.deleteDataStore();

      expect(result, isNull);
      verify(() => mockBiometricStorageFile.delete()).called(1);
    });

    test('readDataFromStore combines data on Windows platform', () async {
      when(() => mockBiometricStorageFile.read())
          .thenAnswer((_) async => '2'); // Simulate 2 segments
      when(() => mockBiometricStorage.getStorage(any(), options: any(named: 'options')))
          .thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read())
          .thenAnswer((_) async => 'segment1');

      final result = await keyChainStorage.readDataFromStore(
        store: mockBiometricStorageFile,
      );

      expect(result, 'segment1segment2');
    });
  });
}