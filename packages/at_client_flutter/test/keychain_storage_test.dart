import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/keychain/keychain_data.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';
import 'package:mocktail/mocktail.dart';

import 'data/keychain_data.dart';

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
        },
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel('biometric_storage'), (
        MethodCall methodCall,
      ) async {
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
        ''',
          };
        }
        return false;
      });
  group('AtKeysData Tests', () {
    late KeychainStorage keyChainStorage;
    late MockBiometricStorage mockBiometricStorage;
    late MockBiometricStorageFile mockBiometricStorageFile;

    setUp(() {
      mockBiometricStorage = MockBiometricStorage();
      mockBiometricStorageFile = MockBiometricStorageFile();
      keyChainStorage = KeychainStorage();
      keyChainStorage.biometricStorage = mockBiometricStorage;
    });

    test('readAtKeys returns AtKeys if data exists', () async {
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => dummyAtKeysData);

      final result = await keyChainStorage.readAtKeysData();

      expect(result, isNotNull);
      expect(result.runtimeType, AtKeysData);
    });

    test('readAtKeys returns null if no data exists', () async {
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => null);

      final result = await keyChainStorage.readAtKeysData();

      expect(result, isNull);
    });

    test('appendAtKeys saves data successfully', () async {
      String fakeAtKeysData = "{'key': 'value'}";
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => null);
      when(() => mockBiometricStorageFile.write(any())).thenAnswer((
        invocation,
      ) async {
        fakeAtKeysData = invocation.positionalArguments[0] as String;
        return Future.value();
      });

      await keyChainStorage.appendAtKeysToKeychain(keys: dummyAtKeys);
      expect(fakeAtKeysData, isNotEmpty);
      expect(fakeAtKeysData == "{'key': 'value'}", isFalse);
      expect(
        AtKeysData.fromJson(jsonDecode(fakeAtKeysData)).runtimeType,
        AtKeysData,
      );
    });

    test('appendAtKeys throws exception on biometricStorage failure', () async {
      final atKeys = AtKeys.fromJson({'key': 'value'});
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.write(any())).thenThrow(Exception());

      expect(
        () async => await keyChainStorage.appendAtKeysToKeychain(keys: atKeys),
        throwsA(isA<Exception>()),
      );
    });

    test('deleteAllAtKeysData deletes data successfully', () async {
      String? atKeysData = dummyAtKeysData;
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.delete()).thenAnswer((_) async {
        atKeysData = null;
        return Future.value();
      });
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => atKeysData);

      expect(
        () async => keyChainStorage.deleteAllAtKeysData(),
        returnsNormally,
      );
      final result = await keyChainStorage.readAtKeysData();
      expect(result, isNull);
    });

    test('readAtKeysData combines data on Windows platform', () async {
      KeychainStorage.isWindows = true;
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => '{"segmentCount": 2}'); // Simulate 2 segments
      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:test',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      MockBiometricStorageFile segment1Storage = MockBiometricStorageFile();
      MockBiometricStorageFile segment2Storage = MockBiometricStorageFile();

      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:test_segment_0',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => segment1Storage);
      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:test_segment_1',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => segment2Storage);
      String split1 = dummyAtKeysData.substring(
        0,
        (dummyAtKeysData.length / 2).ceil(),
      );
      String split2 = dummyAtKeysData.substring(
        (dummyAtKeysData.length / 2).ceil(),
      );
      when(() => segment1Storage.read()).thenAnswer((_) async => split1);
      when(() => segment2Storage.read()).thenAnswer((_) async => split2);

      final result = await keyChainStorage.readAtKeysData();

      expect(result, isNotNull);
      final string = jsonEncode(result!.toJson());
      expect(string, equals(dummyAtKeysData));
    });

    tearDown(() {
      KeychainStorage.isWindows = false;
      reset(mockBiometricStorage);
      reset(mockBiometricStorageFile);
    });
  });

  group('EnrollmentData Tests', () {
    late KeychainStorage keyChainStorage;
    late MockBiometricStorage mockBiometricStorage;
    late MockBiometricStorageFile mockBiometricStorageFile;
    String alice = '@alice';

    setUp(() {
      mockBiometricStorage = MockBiometricStorage();
      mockBiometricStorageFile = MockBiometricStorageFile();
      keyChainStorage = KeychainStorage(biometricStorage: mockBiometricStorage);
    });

    test('readEnrollmentData returns EnrollmentData if data exists', () async {
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => dummyEnrollmentData);

      final result = await keyChainStorage.readEnrollmentData(alice);

      expect(result, isNotNull);
      expect(result.runtimeType, EnrollmentData);
      expect(result?.enrollmentId, 'enrollId1');
    });

    test('readEnrollmentData returns null if no data exists', () async {
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => null);

      final result = await keyChainStorage.readEnrollmentData(alice);

      expect(result, isNull);
    });

    tearDown(() {
      reset(mockBiometricStorage);
      reset(mockBiometricStorageFile);
    });
  });

  group("Legacy Keychain Support", () {
    late KeychainStorage keyChainStorage;
    late MockBiometricStorage mockBiometricStorage;
    late MockBiometricStorageFile mockBiometricStorageFile;

    // Enrollment Schema hasn't changed, so no tests needed for that.

    setUp(() {
      resetMocktailState();
      mockBiometricStorage = MockBiometricStorage();
      mockBiometricStorageFile = MockBiometricStorageFile();
      keyChainStorage = KeychainStorage();
      keyChainStorage.biometricStorage = mockBiometricStorage;
    });

    tearDown(() {
      // Reset unconditionally so a failing Windows test can't leak
      // isWindows = true into whichever test runs next.
      KeychainStorage.isWindows = false;
    });

    test('AtClientData to AtKeysData: legacy name field', () async {
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => legacyAtClientData);

      final result = await keyChainStorage.readAtKeysData();
      expect(result, isNotNull);
      expect(result?.keys.length, 2);
      expect(result?.defaultAtsign, '@alice');
      expect(result?.keys[0].apkamPrivateKey, isNotNull);
      expect(result?.keys[0].apkamPublicKey, isNotNull);
      expect(result?.keys[0].defaultSelfEncryptionKey, isNotNull);
      expect(result?.keys[0].defaultEncryptionPrivateKey, isNotNull);
      expect(result?.keys[0].defaultEncryptionPublicKey, isNotNull);
      expect(result?.keys[0].apkamSymmetricKey, isNotNull);
      expect(result?.keys[0].enrollmentId, 'enrollId1');
      expect(result?.keys[0].metadata['hiveSecret'], isNotNull);
      expect(result?.keys[0].metadata['secret'], isNotNull);
      expect(result?.keys[0].metadata['name'], '@alice');
    });

    test('readAtKeysData combines data on Windows platform', () async {
      KeychainStorage.isWindows = true;
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => '2'); // Simulate 2 segments
      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:test',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      MockBiometricStorageFile segment1Storage = MockBiometricStorageFile();
      MockBiometricStorageFile segment2Storage = MockBiometricStorageFile();

      when(
        () => mockBiometricStorage.getStorage(
          'test_data_0',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => segment1Storage);
      when(
        () => mockBiometricStorage.getStorage(
          'test_data_1',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => segment2Storage);
      String split1 = dummyAtKeysData.substring(
        0,
        (dummyAtKeysData.length / 2).ceil(),
      );
      String split2 = dummyAtKeysData.substring(
        (dummyAtKeysData.length / 2).ceil(),
      );
      when(() => segment1Storage.read()).thenAnswer((_) async => split1);
      when(() => segment2Storage.read()).thenAnswer((_) async => split2);

      final result = await keyChainStorage.readAtKeysData();

      expect(result, isNotNull);
      final string = jsonEncode(result!.toJson());
      expect(string, equals(dummyAtKeysData));
      KeychainStorage.isWindows = false;
    });

    test('AtKeysData schema equivalence check', () async {
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => dummyAtKeysData);
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      final result = await keyChainStorage.readAtKeysData();
      expect(result, isNotNull);
      expect(checkSchemaEquality(result!), isTrue);
    });

    test(
      'readAtKeysData migrates data from legacy `_` delimited store name',
      () async {
        MockBiometricStorageFile legacyStorageFile = MockBiometricStorageFile();

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => mockBiometricStorageFile);
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => null);
        when(
          () => mockBiometricStorageFile.write(any()),
        ).thenAnswer((_) async {});

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacyStorageFile);
        when(
          () => legacyStorageFile.read(),
        ).thenAnswer((_) async => dummyAtKeysData);

        final result = await keyChainStorage.readAtKeysData();

        expect(result, isNotNull);
        expect(result?.defaultAtsign, '@alice');
        verify(() => mockBiometricStorageFile.write(dummyAtKeysData)).called(1);
        verifyNever(() => legacyStorageFile.delete());
      },
    );

    test(
      'appendAtKeysToKeychain migrates legacy data before appending',
      () async {
        MockBiometricStorageFile legacyStorageFile = MockBiometricStorageFile();

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => mockBiometricStorageFile);
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => null);
        when(
          () => mockBiometricStorageFile.write(any()),
        ).thenAnswer((_) async {});

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacyStorageFile);
        when(
          () => legacyStorageFile.read(),
        ).thenAnswer((_) async => dummyAtKeysData);

        await keyChainStorage.appendAtKeysToKeychain(keys: dummyAtKeys);

        final captured = verify(
          () => mockBiometricStorageFile.write(captureAny()),
        ).captured;
        // One write to migrate the legacy data as-is, one to persist the
        // appended key.
        expect(captured.length, 2);
        final finalData = AtKeysData.fromJson(
          jsonDecode(captured.last as String),
        );
        expect(finalData.keys.length, 2);
        expect(finalData.defaultAtsign, '@alice');
        verifyNever(() => legacyStorageFile.delete());
      },
    );

    test(
      'removeAtsignFromKeychain migrates legacy data before removing',
      () async {
        MockBiometricStorageFile legacyStorageFile = MockBiometricStorageFile();

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => mockBiometricStorageFile);
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => null);
        when(
          () => mockBiometricStorageFile.write(any()),
        ).thenAnswer((_) async {});

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacyStorageFile);
        when(
          () => legacyStorageFile.read(),
        ).thenAnswer((_) async => dummyAtKeysData);

        await keyChainStorage.removeAtsignFromKeychain('@alice');

        verify(() => mockBiometricStorageFile.write(any())).called(2);
        verifyNever(() => legacyStorageFile.delete());
      },
    );

    test(
      'readAtKeysData returns null when the legacy store read throws',
      () async {
        MockBiometricStorageFile legacyStorageFile = MockBiometricStorageFile();

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => mockBiometricStorageFile);
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => null);

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacyStorageFile);
        when(() => legacyStorageFile.read()).thenThrow(Exception('boom'));
        when(() => legacyStorageFile.write(any())).thenAnswer((_) async {});

        final result = await keyChainStorage.readAtKeysData();

        expect(result, isNull);
        verifyNever(() => mockBiometricStorageFile.write(any()));
      },
    );

    test(
      'readAtKeysData migrates legacy `_` delimited store data on Windows platform',
      () async {
        KeychainStorage.isWindows = true;

        MockBiometricStorageFile legacyStorageFile = MockBiometricStorageFile();
        MockBiometricStorageFile legacySegment0 = MockBiometricStorageFile();
        MockBiometricStorageFile legacySegment1 = MockBiometricStorageFile();
        MockBiometricStorageFile newSegment0 = MockBiometricStorageFile();
        MockBiometricStorageFile newSegment1 = MockBiometricStorageFile();

        // No data yet under the `:` store.
        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => mockBiometricStorageFile);
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => null);
        when(
          () => mockBiometricStorageFile.write(any()),
        ).thenAnswer((_) async {});

        // Legacy `_` store holds segmented data.
        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacyStorageFile);
        when(
          () => legacyStorageFile.read(),
        ).thenAnswer((_) async => '{"segmentCount": 2}');

        String split1 = dummyAtKeysData.substring(
          0,
          (dummyAtKeysData.length / 2).ceil(),
        );
        String split2 = dummyAtKeysData.substring(
          (dummyAtKeysData.length / 2).ceil(),
        );

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test_segment_0',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacySegment0);
        when(() => legacySegment0.read()).thenAnswer((_) async => split1);
        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test_segment_1',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacySegment1);
        when(() => legacySegment1.read()).thenAnswer((_) async => split2);

        // Migration writes the combined data back out under `:`. The
        // combined data here is well under the 2560-byte segment
        // threshold, so it re-splits into a single output segment even
        // though it was read back from 2 legacy segments.
        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test_segment_0',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => newSegment0);
        when(() => newSegment0.write(any())).thenAnswer((_) async {});
        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test_segment_1',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => newSegment1);
        when(() => newSegment1.write(any())).thenAnswer((_) async {});

        final result = await keyChainStorage.readAtKeysData();

        expect(result, isNotNull);
        expect(result?.defaultAtsign, '@alice');
        verify(() => mockBiometricStorageFile.write(any())).called(1);
        verify(() => newSegment0.write(any())).called(1);
        verifyNever(() => newSegment1.write(any()));
        verifyNever(() => legacyStorageFile.delete());
      },
    );

    test('deleteAllAtKeysData only clears the `:` store; legacy `_` data '
        'survives and is picked back up on the next read', () async {
      MockBiometricStorageFile legacyStorageFile = MockBiometricStorageFile();

      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns:test',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      when(() => mockBiometricStorageFile.delete()).thenAnswer((_) async {});

      when(
        () => mockBiometricStorage.getStorage(
          '@atsigns_test',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => legacyStorageFile);

      await keyChainStorage.deleteAllAtKeysData();

      verifyNever(() => legacyStorageFile.read());
      verifyNever(() => legacyStorageFile.write(any()));
      verifyNever(() => legacyStorageFile.delete());

      // Legacy data is untouched, so it's still there for the next read,
      // and gets migrated forward again.
      when(() => mockBiometricStorageFile.read()).thenAnswer((_) async => null);
      when(
        () => mockBiometricStorageFile.write(any()),
      ).thenAnswer((_) async {});
      when(
        () => legacyStorageFile.read(),
      ).thenAnswer((_) async => dummyAtKeysData);

      final result = await keyChainStorage.readAtKeysData();

      expect(result, isNotNull);
      expect(result?.defaultAtsign, '@alice');
    });

    test('EnrollmentData schema equivalence check', () async {
      when(
        () => mockBiometricStorageFile.read(),
      ).thenAnswer((_) async => dummyEnrollmentData);
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      final result = await keyChainStorage.readEnrollmentData('@alice');
      expect(result, isNotNull);
      expect(checkSchemaEquality(result!), isTrue);
    });
  });
}
