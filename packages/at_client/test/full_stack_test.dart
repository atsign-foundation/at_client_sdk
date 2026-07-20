import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/no_op_services.dart';
import 'test_utils/mocks.dart';

bool wrappedDecryptSucceeds(
    {required String cipherText,
    required String aesKey,
    required String? ivBase64,
    required String clearText}) {
  try {
    var deciphered =
        EncryptionUtil.decryptValue(cipherText, aesKey, ivBase64: ivBase64);
    if (deciphered != clearText) {
      return false;
    } else {
      return true;
    }
  } catch (e) {
    return false;
  }
}

void main() {
  var namespace = 'full_stack_tests';
  group('Test with full client stack except mockRemoteSecondary', () {
    final fullStackPrefs = AtClientPreference()
      ..namespace = namespace
      ..hiveStoragePath = '$namespace/put/hive'
      ..commitLogPath = '$namespace/put/commitLog';

    late MockRemoteSecondary mockRemoteSecondary;
    late AtClientImpl atClient;
    late LocalSecondary localSecondary;

    var clearText = 'Some clear text';

    RSAKeypair alicesRSAKeyPair = RSAKeypair.fromRandom();
    RSAKeypair bobsRSAKeyPair = RSAKeypair.fromRandom();
    RSAKeypair victorsRSAKeyPair = RSAKeypair.fromRandom();

    AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
        alicesRSAKeyPair.publicKey.toString(),
        alicesRSAKeyPair.privateKey.toString());

    var selfEncryptionKey = EncryptionUtil.generateAESKey();

    var bobSharedKey = EncryptionUtil.generateAESKey();
    var myEncryptedBobSharedKey = EncryptionUtil.encryptKey(
        bobSharedKey, alicesRSAKeyPair.publicKey.toString());
    var llookupMySharedKeyForBob = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = '${AtConstants.atEncryptionSharedKey}.bob'
        ..sharedBy = '@alice');

    var victorSymKey = EncryptionUtil.generateAESKey();
    var myEncryptedVicSymKey = EncryptionUtil.encryptKey(
        victorSymKey, alicesRSAKeyPair.publicKey.toString());

    late Map<String, dynamic> remoteLLookupMap;
    late Map<String, dynamic> remotePLookupMap;
    late Map<String, dynamic> remoteUpdatedMap;
    late int remoteCommitId;
    late int remoteLLookupRequestCount;
    late int remotePLookupRequestCount;
    late int remoteUpdateRequestCount;
    late bool remoteSecondaryAvailable;
    late AtKeyValueStore<String, AtData, AtMetaData?> localStore;

    registerFallbackValue(llookupMySharedKeyForBob);

    /// Runs once for this entire group of tests
    setUpAll(() async {
      mockRemoteSecondary = MockRemoteSecondary();
      MockSecondaryAddressFinder mockSecondaryAddressFinder =
          MockSecondaryAddressFinder();
      AtClientManager.getInstance().secondaryAddressFinder =
          mockSecondaryAddressFinder;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((invocation) async => SecondaryAddress('testing', 12));
      AtChopsKeys atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
      atChopsKeys.selfEncryptionKey = AESKey(selfEncryptionKey);
      AtChops atChops = AtChopsImpl(atChopsKeys);

      atClient = (await AtClientImpl.create('@alice', 'gary', fullStackPrefs,
          remoteSecondary: mockRemoteSecondary,
          atChops: atChops)) as AtClientImpl;
      localStore = atClient.getLocalSecondary()!.keyStore!;
      localSecondary = atClient.getLocalSecondary()!;
      atClient.syncService = NoOpSyncService();

      // Create our symmetric 'self' encryption key
      await atClient
          .getLocalSecondary()!
          .putValue(AtConstants.atEncryptionSelfKey, selfEncryptionKey);

      await atClient.getLocalSecondary()!.putValue(
          'public:publickey@alice', alicesRSAKeyPair.publicKey.toString());
      // Create our symmetric encryption key for sharing with @bob
      await atClient
          .getLocalSecondary()!
          .putValue('shared_key.bob@alice', myEncryptedBobSharedKey);
    });

    String myCopyVicSymKeyName = 'shared_key.victor@alice';

    /// Runs for every test
    setUp(() async {
      await localStore.remove(myCopyVicSymKeyName);

      atClient.localSecondary = localSecondary;
      fullStackPrefs.remoteLocalPref = RemoteLocalPref.localOnly;
      remoteSecondaryAvailable = true;

      remotePLookupMap = {};
      remotePLookupRequestCount = 0;
      remotePLookupMap['publickey@bob'] = bobsRSAKeyPair.publicKey.toString();
      remotePLookupMap['publickey@victor'] =
          victorsRSAKeyPair.publicKey.toString();
      when(() => mockRemoteSecondary.executeVerb(
          any(that: isA<PLookupVerbBuilder>()))).thenAnswer((invocation) async {
        remotePLookupRequestCount++;
        var builder = invocation.positionalArguments[0] as PLookupVerbBuilder;
        print('PLookupVerbBuilder : ${builder.buildCommand()}');
        if (!remoteSecondaryAvailable) {
          print("Mock RemoteSecondary throwing SecondaryConnectException");
          throw SecondaryConnectException(
              'Mock remote atServer is unavailable');
        }
        var val =
            remotePLookupMap['${builder.atKey.key}${builder.atKey.sharedBy}'];
        if (val != null) {
          return val;
        } else {
          throw KeyNotFoundException(
              'No value in mock remote for PLookup: ${builder.buildCommand()}');
        }
      });

      remoteLLookupMap = {};
      remoteLLookupRequestCount = 0;
      remoteLLookupMap['shared_key.bob@alice'] = myEncryptedBobSharedKey;
      when(() => mockRemoteSecondary.executeVerb(
          any(that: isA<LLookupVerbBuilder>()))).thenAnswer((invocation) async {
        remoteLLookupRequestCount++;
        var builder = invocation.positionalArguments[0] as LLookupVerbBuilder;
        print('LLookupVerbBuilder : ${builder.buildCommand()}');
        if (!remoteSecondaryAvailable) {
          print("Mock RemoteSecondary throwing SecondaryConnectException");
          throw SecondaryConnectException(
              'Mock remote atServer is unavailable');
        }
        var val = remoteLLookupMap[builder.atKey.toString()];
        if (val != null) {
          return val;
        } else {
          throw KeyNotFoundException(
              'No value in mock remote for LLookup: ${builder.buildCommand()}');
        }
      });

      remoteUpdatedMap = {};
      remoteCommitId = 1;
      remoteUpdateRequestCount = 0;
      when(() => mockRemoteSecondary.executeVerb(
          any(that: isA<UpdateVerbBuilder>()),
          sync: any(named: "sync"))).thenAnswer((invocation) async {
        remoteUpdateRequestCount++;
        var builder = invocation.positionalArguments[0] as UpdateVerbBuilder;
        print('UpdateVerbBuilder : ${builder.buildCommand()}');
        if (!remoteSecondaryAvailable) {
          print("Mock RemoteSecondary throwing SecondaryConnectException");
          throw SecondaryConnectException(
              'Mock remote atServer is unavailable');
        }
        remoteUpdatedMap[builder.atKey.toString()] = builder.value;
        return 'data:${remoteCommitId++}';
      });
    });

    group('Test encryption for self', () {
      test('Test put self, then get, with IV', () async {
        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNotNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData!.data!;
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            EncryptionUtil.decryptValue(cipherText, selfEncryptionKey,
                ivBase64: atKey.metadata.ivNonce),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });
    });

    group('Test encryption for sharing', () {
      test('Test put shared, then get, with IV', () async {
        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNotNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData!.data!;
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: atKey.metadata.ivNonce,
                clearText: clearText),
            false);
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: bobSharedKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            EncryptionUtil.decryptValue(cipherText, bobSharedKey,
                ivBase64: atKey.metadata.ivNonce),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });
    });

    group('Tests for PutRequestOptions.useRemoteAtServer', () {
      test('PutRequestOptions.useRemoteAtServer defaults to false', () {
        PutRequestOptions pro = PutRequestOptions();
        expect(pro.useRemoteAtServer, false);
      });
      checkPutBehaviour(
        bool? useRemoteAtServer,
        RemoteLocalPref remoteLocalPref,
      ) async {
        bool executedRemotely = false;
        bool executedLocally = false;
        var atKey = (AtKey.shared('test_put')
              ..sharedWith('@alice')
              ..sharedBy('@alice'))
            .build();

        MockLocalSecondary mockLocalSecondary =
            atClient.localSecondary = MockLocalSecondary();

        when(() => mockLocalSecondary.executeVerb(
            any(that: isA<UpdateVerbBuilder>()),
            sync: any(named: "sync"))).thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as UpdateVerbBuilder;
          if (builder.atKey.toString() == atKey.toString()) {
            // print('mockLocalSecondary.executeVerb with UpdateVerbBuilder'
            //     ' for ${builder.atKey.toString()} as expected');
            executedLocally = true;
            return 'data:20';
          } else {
            print(builder.buildCommand());
            throw Exception(
                'mockLocalSecondary.executeVerb called with unexpected UpdateVerbBuilder');
          }
        });

        when(() => mockRemoteSecondary.executeVerb(
            any(that: isA<UpdateVerbBuilder>()),
            sync: any(named: "sync"))).thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as UpdateVerbBuilder;
          if (builder.atKey.toString() == atKey.toString()) {
            // print('mockRemoteSecondary.executeVerb with UpdateVerbBuilder'
            //     ' for ${builder.atKey.toString()} as expected');
            executedRemotely = true;
            return 'data:10';
          } else if (builder.atKey.toString() == '@bob:shared_key@alice') {
            return 'data:10';
          } else {
            print(builder.buildCommand());
            throw Exception(
                'mockRemoteSecondary.executeVerb called with unexpected UpdateVerbBuilder');
          }
        });

        var selfEncryptionKeyID = AtKey()
          ..key =
              '${AtConstants.atEncryptionSharedKey}.${atKey.sharedWith?.replaceAll('@', '')}'
          ..sharedBy = atKey.sharedBy;

        when(() => mockLocalSecondary
                .executeVerb(any(that: isA<LLookupVerbBuilder>())))
            .thenAnswer((invocation) async {
          remoteLLookupRequestCount++;
          var builder = invocation.positionalArguments[0] as LLookupVerbBuilder;
          print('LLookupVerbBuilder : ${builder.buildCommand()}');
          if (builder.atKey.toString() == selfEncryptionKeyID.toString()) {
            return 'data:$selfEncryptionKey';
          } else {
            throw KeyNotFoundException(
                'No value in mock local for LLookup: ${builder.buildCommand()}');
          }
        });

        atClient.getPreferences()!.remoteLocalPref = remoteLocalPref;

        PutRequestOptions? putRequestOptions;
        if (useRemoteAtServer != null) {
          putRequestOptions = PutRequestOptions()
            ..useRemoteAtServer = useRemoteAtServer;
        }
        var retVal = await atClient.put(atKey, clearText,
            putRequestOptions: putRequestOptions);

        if (useRemoteAtServer == true) {
          expect(executedRemotely, true);
          expect(executedLocally, false);
          expect(retVal, true);
        } else if (useRemoteAtServer == false) {
          expect(executedRemotely, false);
          expect(executedLocally, true);
          expect(retVal, true);
        } else {
          // useRemoteAtServer is null
          switch (remoteLocalPref) {
            case RemoteLocalPref.localOnly:
              expect(executedRemotely, false);
              expect(executedLocally, true);
              expect(retVal, true);
            case RemoteLocalPref.remoteOnly:
              expect(executedRemotely, true);
              expect(executedLocally, false);
              expect(retVal, true);
          }
        }
      }

      test('put behaviour when PutRequestOptions.useRemoteAtServer is true',
          () async {
        await checkPutBehaviour(true, RemoteLocalPref.localOnly);
        await checkPutBehaviour(true, RemoteLocalPref.remoteOnly);
      });
      test('put behaviour when PutRequestOptions.useRemoteAtServer is false',
          () async {
        await checkPutBehaviour(false, RemoteLocalPref.localOnly);
        await checkPutBehaviour(false, RemoteLocalPref.remoteOnly);
      });
      test('put behaviour when PutRequestOptions.useRemoteAtServer is null',
          () async {
        await checkPutBehaviour(null, RemoteLocalPref.localOnly);
        await checkPutBehaviour(null, RemoteLocalPref.remoteOnly);
      });
    });

    group('Tests for DeleteRequestOptions.useRemoteAtServer', () {
      test('DeleteRequestOptions.useRemoteAtServer defaults to false', () {
        DeleteRequestOptions dro = DeleteRequestOptions();
        expect(dro.useRemoteAtServer, false);
      });
      checkDeleteBehaviour(
        bool? useRemoteAtServer,
        RemoteLocalPref remoteLocalPref,
      ) async {
        bool executedRemotely = false;
        bool executedLocally = false;
        var atKey = (AtKey.shared('test_put',
                namespace: namespace, sharedBy: atClient.getCurrentAtSign()!)
              ..sharedWith('@bob'))
            .build();
        print(atKey.toString());

        MockLocalSecondary mockLocalSecondary =
            atClient.localSecondary = MockLocalSecondary();
        when(() => mockLocalSecondary.executeVerb(
            any(that: isA<DeleteVerbBuilder>()),
            sync: any(named: "sync"))).thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as DeleteVerbBuilder;
          // print('DeleteVerbBuilder: ${builder.buildCommand()}');
          if (builder.buildKey() == atKey.toString()) {
            executedLocally = true;
            return 'data:20';
          } else {
            print(builder.buildCommand());
            throw Exception(
                'mockLocalSecondary.executeVerb called with unexpected DeleteVerbBuilder');
          }
        });
        when(() => mockRemoteSecondary.executeVerb(
            any(that: isA<DeleteVerbBuilder>()),
            sync: any(named: "sync"))).thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as DeleteVerbBuilder;
          print('DeleteVerbBuilder: ${builder.buildCommand()}');
          if (builder.buildKey() == atKey.toString()) {
            // print('mockRemoteSecondary.executeVerb with DeleteVerbBuilder'
            //     ' for ${builder.atKey.toString()} as expected');
            executedRemotely = true;
            return 'data:10';
          } else {
            print(builder.buildCommand());
            throw Exception(
                'mockRemoteSecondary.executeVerb called with unexpected DeleteVerbBuilder');
          }
        });
        atClient.getPreferences()!.remoteLocalPref = remoteLocalPref;
        DeleteRequestOptions? deleteRequestOptions;
        if (useRemoteAtServer != null) {
          deleteRequestOptions = DeleteRequestOptions()
            ..useRemoteAtServer = useRemoteAtServer;
        }
        var retVal = await atClient.delete(atKey,
            deleteRequestOptions: deleteRequestOptions);
        if (useRemoteAtServer == true) {
          expect(executedRemotely, true);
          expect(executedLocally, false);
          expect(retVal, true);
        } else if (useRemoteAtServer == false) {
          expect(executedRemotely, false);
          expect(executedLocally, true);
          expect(retVal, true);
        } else {
          // useRemoteAtServer is null
          switch (remoteLocalPref) {
            case RemoteLocalPref.localOnly:
              expect(executedRemotely, false);
              expect(executedLocally, true);
              expect(retVal, true);
            case RemoteLocalPref.remoteOnly:
              expect(executedRemotely, true);
              expect(executedLocally, false);
              expect(retVal, true);
          }
        }
      }

      test(
          'delete behaviour when DeleteRequestOptions.useRemoteAtServer is true',
          () async {
        await checkDeleteBehaviour(true, RemoteLocalPref.localOnly);
        await checkDeleteBehaviour(true, RemoteLocalPref.remoteOnly);
      });
      test(
          'delete behaviour when DeleteRequestOptions.useRemoteAtServer is false',
          () async {
        await checkDeleteBehaviour(false, RemoteLocalPref.localOnly);
        await checkDeleteBehaviour(false, RemoteLocalPref.remoteOnly);
      });
      test(
          'delete behaviour when DeleteRequestOptions.useRemoteAtServer is null',
          () async {
        await checkDeleteBehaviour(null, RemoteLocalPref.localOnly);
        await checkDeleteBehaviour(null, RemoteLocalPref.remoteOnly);
      });
    });

    group('Tests for scan with useRemoteAtServer', () {
      test('Scan useRemoteAtServer defaults to false', () async {
        bool executedRemotely = false;
        // Scan; verify that the RemoteSecondary was NOT invoked
        when(() => mockRemoteSecondary.executeVerb(
            any(that: isA<ScanVerbBuilder>()))).thenAnswer((invocation) async {
          executedRemotely = true;
          return 'data:[]';
        });
        await atClient.getAtKeys();
        expect(executedRemotely, false);
      });
      test('Scan when useRemoteAtServer set to true', () async {
        bool executedRemotely = false;
        // Scan; verify that the RemoteSecondary was NOT invoked
        when(() => mockRemoteSecondary.executeVerb(
            any(that: isA<ScanVerbBuilder>()))).thenAnswer((invocation) async {
          executedRemotely = true;
          return 'data:[]';
        });
        await atClient.getAtKeys(useRemoteAtServer: true);
        expect(executedRemotely, true);
      });
      test(
          'Scan when useRemoteAtServer is false, with various values of remoteLocalPref',
          () async {
        bool executedRemotely = false;
        when(() => mockRemoteSecondary.executeVerb(
            any(that: isA<ScanVerbBuilder>()))).thenAnswer((invocation) async {
          executedRemotely = true;
          return 'data:[]';
        });
        atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.localOnly;
        await atClient.getAtKeys();
        expect(executedRemotely, false);

        atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;
        await atClient.getAtKeys();
        expect(executedRemotely, true);
      });
    });
    group('Tests for GetRequestOptions.useRemoteAtServer', () {
      test('GetRequestOptions.useRemoteAtServer defaults to false', () {
        GetRequestOptions gro = GetRequestOptions();
        expect(gro.useRemoteAtServer, false);
      });

      test(
          'get self key useRemoteAtServer null, various remoteLocalPref values',
          () async {
        bool executedRemotely = false;
        // Make a self key - by default, this will be looked up locally using
        // an LLookup
        var atKey = AtKey.fromString('test_get_self_key_when_remote_is_false'
            '.${atClient.getPreferences()!.namespace!}'
            '${atClient.getCurrentAtSign()!}');
        when(() => mockRemoteSecondary
                .executeVerb(any(that: isA<LLookupVerbBuilder>())))
            .thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as LLookupVerbBuilder;
          if (builder.atKey.toString() == atKey.toString()) {
            // print('mockRemoteSecondary.executeVerb with LLookupVerbBuilder'
            //     ' for ${builder.atKey.toString()} - this is NOT expected');
            executedRemotely = true;
            return 'data:null';
          } else {
            return 'data:null';
          }
        });

        dynamic caught;

        atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.localOnly;
        caught = null;
        try {
          await atClient.get(atKey, getRequestOptions: null);
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<AtKeyNotFoundException>());
        expect(executedRemotely, false);

        atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;
        caught = null;
        try {
          await atClient.get(atKey, getRequestOptions: null);
        } catch (e) {
          caught = e;
        }
        expect(caught, isNull);
        expect(executedRemotely, true);
      });

      test(
          'get self key useRemoteAtServer false, various remoteLocalPref values',
          () async {
        bool executedRemotely = false;

        var atKey = AtKey.fromString('test_get_self_key_when_remote_is_false'
            '.${atClient.getPreferences()!.namespace!}'
            '${atClient.getCurrentAtSign()!}');

        dynamic caught;

        atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.localOnly;
        caught = null;
        try {
          await atClient.get(atKey,
              getRequestOptions: GetRequestOptions()
                ..useRemoteAtServer = false);
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<AtKeyNotFoundException>());
        expect(executedRemotely, false);

        atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;
        caught = null;
        try {
          await atClient.get(atKey,
              getRequestOptions: GetRequestOptions()
                ..useRemoteAtServer = false);
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<AtKeyNotFoundException>());
        expect(executedRemotely, false);
      });

      test('get self key when useRemoteAtServer set to true', () async {
        bool executedRemotely = false;
        // Make a self key - by default, this will be looked up locally
        var atKey = AtKey.fromString('test_get_self_key_when_remote_is_true'
            '.${atClient.getPreferences()!.namespace!}'
            '${atClient.getCurrentAtSign()!}');
        when(() => mockRemoteSecondary
                .executeVerb(any(that: isA<LLookupVerbBuilder>())))
            .thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as LLookupVerbBuilder;
          if (builder.atKey.toString() == atKey.toString()) {
            print('mockRemoteSecondary.executeVerb with LLookupVerbBuilder'
                ' for ${builder.atKey.toString()} as expected');
            executedRemotely = true;
            return 'data:null';
          } else {
            return 'data:null';
          }
        });
        dynamic caught;
        try {
          await atClient.get(atKey,
              getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
        } catch (e) {
          caught = e;
        }
        expect(caught, isNull);
        expect(executedRemotely, true);
      });
    });

    group(
        'Verify that my new shared symmetric keys are sent first to remote atServer',
        () {
      AtKey fooBarForVictor = AtKey.fromString('@victor:foo.bar@alice');

      // 1. My copy not found in local, atServer unavailable ? => exception
      test(
          'exception thrown if no local my copy of shared key and atServer is unavailable',
          () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        remoteSecondaryAvailable = false;
        await expectLater(ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor),
            throwsA(isA<SecondaryConnectException>()));
        expect(remotePLookupRequestCount, 0);
        expect(remoteLLookupRequestCount, 1);
      });

      // 2. My copy not found in local, not found in atServer => create new
      //   and save to atServer, then local.
      test(
          'if no my copy locally or on atServer, generate new and store remote and local',
          () async {
        // key not available
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        var decryptedSymmetricKey =
            await ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor);
        expect(decryptedSymmetricKey, '');
        expect(remoteUpdateRequestCount, 0); // no updates to atServer
        expect(remotePLookupRequestCount, 0);
        expect(remoteLLookupRequestCount, 1); // lookup 'my' copy on atServer

        // 2b. atServer available - new key should be created in remote and in local
        remoteSecondaryAvailable = true;
        await ske.createLegacySharedSymmetricKey(fooBarForVictor);
        expect(remoteLLookupRequestCount, 1); // still the same

        // We've written two copies (us and them) to atServer
        expect(remoteUpdateRequestCount, 2);
        expect(remoteUpdatedMap[myCopyVicSymKeyName] != null, true);
        expect(await localStore.exists(myCopyVicSymKeyName), true);
      });

      // 3. My copy not found in local, found in atServer => save to local
      test('no my copy locally, but found on atServer, so should store locally',
          () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        expect(await localStore.exists(myCopyVicSymKeyName), false);
        remoteLLookupMap[myCopyVicSymKeyName] = myEncryptedVicSymKey;

        var decryptedSymmetricKey =
            await ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor);
        expect(decryptedSymmetricKey, victorSymKey);
        expect(await localStore.exists(myCopyVicSymKeyName), true);
      });

      // 4. My copy found locally, make no request to atServer
      test('my copy found locally, no LLookup request to atServer', () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        await atClient
            .getLocalSecondary()!
            .putValue(myCopyVicSymKeyName, myEncryptedVicSymKey);
        expect(await localStore.exists(myCopyVicSymKeyName), true);

        var decryptedSymmetricKey =
            await ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor);
        expect(decryptedSymmetricKey, victorSymKey);
        expect(remoteLLookupRequestCount, 0);
        expect(remotePLookupRequestCount, 0);
      });
    });
  });
}
