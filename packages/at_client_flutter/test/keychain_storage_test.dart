import 'dart:async';
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

    test('a failing read leaves the stored key material intact', () async {
      when(
        () => mockBiometricStorage.getStorage(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockBiometricStorageFile);
      // NOTE: this store may hold the only copies of the atSign's keys, so a
      // read path that writes on failure turns a transient error into
      // permanent key loss.
      when(
        () => mockBiometricStorageFile.read(),
      ).thenThrow(Exception('platform channel unavailable'));
      when(
        () => mockBiometricStorageFile.write(any()),
      ).thenAnswer((_) async {});

      await expectLater(keyChainStorage.readAtKeysData(), throwsException);

      verifyNever(() => mockBiometricStorageFile.write(any()));
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

      await keyChainStorage.deleteAllAtKeysData();
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

  group("Legacy Keychain Support", () {
    late KeychainStorage keyChainStorage;
    late MockBiometricStorage mockBiometricStorage;
    late MockBiometricStorageFile mockBiometricStorageFile;

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
      expect(result?.keys[0].authenticationKeyPairFor(null), isNotNull);
      expect(result?.keys[0].selfEncryptionKey, isNotNull);
      expect(result?.keys[0].encryptionKeyPair, isNotNull);
      expect(result?.keys[0].enrollmentSymmetricKey, isNotNull);
      expect(result?.keys[0].storedEnrollmentId, 'enrollId1');
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
      'readAtKeysData does not inspect legacy `_` data when `:` data exists',
      () async {
        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => mockBiometricStorageFile);
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => dummyAtKeysData);

        final result = await keyChainStorage.readAtKeysData();

        expect(result, isNotNull);
        expect(result?.defaultAtsign, '@alice');
        verifyNever(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test',
            options: any(named: 'options'),
          ),
        );
        verifyNever(() => mockBiometricStorageFile.write(any()));
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
        verifyNever(() => legacyStorageFile.write(any()));
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

    test(
      'deleteAllAtKeysData clears both Windows stores and their segments',
      () async {
        KeychainStorage.isWindows = true;

        MockBiometricStorageFile legacyStorageFile = MockBiometricStorageFile();
        MockBiometricStorageFile currentSegment0 = MockBiometricStorageFile();
        MockBiometricStorageFile currentSegment1 = MockBiometricStorageFile();
        MockBiometricStorageFile legacySegment0 = MockBiometricStorageFile();

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => mockBiometricStorageFile);
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => '{"segmentCount": 2}');
        when(() => mockBiometricStorageFile.delete()).thenAnswer((_) async {});

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test_segment_0',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => currentSegment0);
        when(() => currentSegment0.delete()).thenAnswer((_) async {});
        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns:test_segment_1',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => currentSegment1);
        when(() => currentSegment1.delete()).thenAnswer((_) async {});

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacyStorageFile);
        when(
          () => legacyStorageFile.read(),
        ).thenAnswer((_) async => '{"segmentCount": 1}');
        when(() => legacyStorageFile.delete()).thenAnswer((_) async {});

        when(
          () => mockBiometricStorage.getStorage(
            '@atsigns_test_segment_0',
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => legacySegment0);
        when(() => legacySegment0.delete()).thenAnswer((_) async {});

        await keyChainStorage.deleteAllAtKeysData();

        verify(() => mockBiometricStorageFile.delete()).called(1);
        verify(() => legacyStorageFile.delete()).called(1);
        verify(() => currentSegment0.delete()).called(1);
        verify(() => currentSegment1.delete()).called(1);
        verify(() => legacySegment0.delete()).called(1);

        // Both stores are gone, so nothing is left to migrate forward.
        when(
          () => mockBiometricStorageFile.read(),
        ).thenAnswer((_) async => null);
        when(() => legacyStorageFile.read()).thenAnswer((_) async => null);

        final result = await keyChainStorage.readAtKeysData();

        expect(result, isNull);
      },
    );
  });

  group('Given only the legacy keychain entry holds the keys', () {
    late KeychainStorage storage;
    late MockBiometricStorage biometricStorage;
    late MockBiometricStorageFile current;
    late MockBiometricStorageFile legacy;
    String? currentEntry;
    late int currentWrites;
    late int heldLegacyReads;
    late int legacyReads;
    late Completer<void> releaseLegacyReads;
    late Completer<void> legacyReadsArrived;

    final AtKeys bobKeys = AtKeys.legacy(
      apkamPrivateKey: 'bobPrivKey12',
      apkamPublicKey: 'bobPubKey123',
      selfEncryptionKey: 'bobSelfKey12',
      encryptionPrivateKey: 'bobEncPrivKey123',
      encryptionPublicKey: 'bobEncPubKey',
      apkamSymmetricKey: 'bobApkamSym1',
      enrollmentId: 'enrollBob',
    );

    setUp(() {
      resetMocktailState();
      biometricStorage = MockBiometricStorage();
      current = MockBiometricStorageFile();
      legacy = MockBiometricStorageFile();
      storage = KeychainStorage()..biometricStorage = biometricStorage;
      currentEntry = null;
      currentWrites = 0;
      legacyReads = 0;
      releaseLegacyReads = Completer<void>();
      legacyReadsArrived = Completer<void>();

      when(
        () => biometricStorage.getStorage(
          '@atsigns:test',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => current);
      when(
        () => biometricStorage.getStorage(
          '@atsigns_test',
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => legacy);
      when(() => current.read()).thenAnswer((_) async => currentEntry);
      when(() => current.write(any())).thenAnswer((inv) async {
        currentEntry = inv.positionalArguments[0] as String;
        currentWrites++;
      });
      // NOTE: the first [heldLegacyReads] reads of the legacy entry wait for
      // [releaseLegacyReads], so a caller can be held part-way through the
      // migration while another runs.
      when(() => legacy.read()).thenAnswer((_) async {
        final held = legacyReads++ < heldLegacyReads;
        if (legacyReads == heldLegacyReads) legacyReadsArrived.complete();
        if (held) await releaseLegacyReads.future;
        return dummyAtKeysData;
      });
    });

    test(
      'when a read and a write of another atSign run at the same moment, then '
      'the current entry keeps both atSigns',
      () async {
        heldLegacyReads = 1;
        final reading = storage.readAtKeysData();
        await legacyReadsArrived.future;

        await storage.appendAtKeysToKeychain(keys: bobKeys);
        releaseLegacyReads.complete();
        await reading;

        final kept = AtKeysData.fromJson(jsonDecode(currentEntry!));
        expect(
          kept.keys.map((k) => k.storedEnrollmentId),
          containsAll(['enrollId1', 'enrollBob']),
          reason:
              'the read must not write the legacy keys back over the '
              'write that migrated them and added another atSign',
        );
      },
    );

    test(
      'when two reads run at the same moment, then the keys are copied to the '
      'current entry once',
      () async {
        heldLegacyReads = 2;
        final first = storage.readAtKeysData();
        final second = storage.readAtKeysData();
        await legacyReadsArrived.future;

        releaseLegacyReads.complete();
        await Future.wait([first, second]);

        expect(currentWrites, 1);
      },
    );
  });
}
