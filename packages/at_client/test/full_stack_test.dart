import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:version/version.dart';

import 'test_utils/no_op_services.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

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
      ..isLocalStoreRequired = true
      ..hiveStoragePath = '$namespace/put/hive'
      ..commitLogPath = '$namespace/put/commitLog';

    late MockRemoteSecondary mockRemoteSecondary;
    late AtClient atClient;

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
    late Set<String> remoteDeletedSet;
    late int remoteCommitId;
    late int remoteLLookupRequestCount;
    late int remotePLookupRequestCount;
    late int remoteUpdateRequestCount;
    late int remoteDeleteRequestCount;
    late bool remoteSecondaryAvailable;
    late SecondaryKeyStore localStore;

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
      atClient = await AtClientImpl.create('@alice', 'gary', fullStackPrefs,
          remoteSecondary: mockRemoteSecondary, atChops: atChops);
      localStore = atClient.getLocalSecondary()!.keyStore!;
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
    String vicsCopySymKeyName = '@victor:shared_key@alice';

    /// Runs for every test
    setUp(() async {
      await localStore.remove(myCopyVicSymKeyName);
      await localStore.remove(vicsCopySymKeyName);

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

      remoteDeletedSet = {};
      remoteDeleteRequestCount = 0;
      when(() => mockRemoteSecondary.executeVerb(
          any(that: isA<DeleteVerbBuilder>()),
          sync: any(named: "sync"))).thenAnswer((invocation) async {
        remoteDeleteRequestCount++;
        var builder = invocation.positionalArguments[0] as DeleteVerbBuilder;
        print('DeleteVerbBuilder : ${builder.buildCommand()}');
        if (!remoteSecondaryAvailable) {
          print("Mock RemoteSecondary throwing SecondaryConnectException");
          throw SecondaryConnectException(
              'Mock remote atServer is unavailable');
        }
        remoteDeletedSet.add(builder.atKey.toString());
        return 'data:${remoteCommitId++}';
      });
    });

    group('Test encryption for self', () {
      test('Test put self, then get, no IV, 1.5 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(EncryptionUtil.decryptValue(cipherText, selfEncryptionKey),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put self, then get, no IV, 1.5 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(EncryptionUtil.decryptValue(cipherText, selfEncryptionKey),
            clearText);

        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);
        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put self, then get, with IV, 2.0 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNotNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
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

      test('Test put self, then get, with IV, 2.0 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNotNull);

        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
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
      test('Test put shared, then get, no IV, 1.5 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            EncryptionUtil.decryptValue(cipherText, bobSharedKey), clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put shared, then get, no IV, 1.5 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNull);

        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);
        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            EncryptionUtil.decryptValue(cipherText, bobSharedKey), clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put shared, then get, with IV, 2.0 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNotNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
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

      test('Test put shared, then get, with IV, 2.0 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata.ivNonce, isNotNull);

        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);
        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
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
      checkPutBehaviour(bool useRemoteAtServer) async {
        bool executedRemotely = false;
        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        when(() => mockRemoteSecondary.executeVerb(
            any(that: isA<UpdateVerbBuilder>()),
            sync: true)).thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as UpdateVerbBuilder;
          if (builder.atKey.toString() == atKey.toString()) {
            print('mockRemoteSecondary.executeVerb with UpdateVerbBuilder'
                ' for ${builder.atKey.toString()} as expected');
            executedRemotely = true;
            return 'data:10';
          } else if (builder.atKey.toString() != '@bob:shared_key@alice') {
            print(builder.buildCommand());
            throw Exception(
                'mockRemoteSecondary.executeVerb called with unexpected UpdateVerbBuilder');
          } else {
            return 'data:10';
          }
        });
        await atClient.put(atKey, clearText,
            putRequestOptions: PutRequestOptions()
              ..useRemoteAtServer = useRemoteAtServer);
        expect(executedRemotely, useRemoteAtServer);
      }

      test('put behaviour when useRemoteAtServer set to true', () async {
        await checkPutBehaviour(true);
      });
      test('put behaviour when useRemoteAtServer set to false', () async {
        await checkPutBehaviour(false);
      });
    });

    group('Tests for DeleteRequestOptions.useRemoteAtServer', () {
      test('DeleteRequestOptions.useRemoteAtServer defaults to false', () {
        DeleteRequestOptions dro = DeleteRequestOptions();
        expect(dro.useRemoteAtServer, false);
      });
      checkDeleteBehaviour(bool useRemoteAtServer) async {
        bool executedRemotely = false;
        var atKey = (AtKey.shared('test_put',
                namespace: namespace, sharedBy: atClient.getCurrentAtSign()!)
              ..sharedWith('@bob'))
            .build();
        print(atKey.toString());
        when(() => mockRemoteSecondary.executeVerb(
            any(that: isA<DeleteVerbBuilder>()),
            sync: true)).thenAnswer((invocation) async {
          var builder = invocation.positionalArguments[0] as DeleteVerbBuilder;
          print('DeleteVerbBuilder: ${builder.buildCommand()}');
          if (builder.buildKey() == atKey.toString()) {
            print('mockRemoteSecondary.executeVerb with DeleteVerbBuilder'
                ' for ${builder.atKey.toString()} as expected');
            executedRemotely = true;
            return 'data:10';
          } else {
            print(builder.buildCommand());
            throw Exception(
                'mockRemoteSecondary.executeVerb called with unexpected DeleteVerbBuilder');
          }
        });
        await atClient.delete(atKey,
            deleteRequestOptions: DeleteRequestOptions()
              ..useRemoteAtServer = useRemoteAtServer);
        expect(executedRemotely, useRemoteAtServer);
      }

      test('delete behaviour when useRemoteAtServer set to true', () async {
        await checkDeleteBehaviour(true);
      });
      test('delete behaviour when useRemoteAtServer set to false', () async {
        await checkDeleteBehaviour(false);
      });
    });

    group('Tests for GetRequestOptions.useRemoteAtServer', () {
      test('GetRequestOptions.useRemoteAtServer defaults to false', () {
        GetRequestOptions gro = GetRequestOptions();
        expect(gro.useRemoteAtServer, false);
      });

      test('get self key when useRemoteAtServer set to false', () async {
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
        try {
          await ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor);
        } catch (e) {
          expect(e is SecondaryConnectException, true);
        }
        expect(remotePLookupRequestCount, 0);
        expect(remoteLLookupRequestCount, 1);
      });

      // 2. My copy not found in local, not found in atServer => create new
      //   and save to atServer, then local.
      test(
          'if no my copy locally or on atServer, generate new and store remote and local',
          () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        var decryptedSymmetricKey =
            await ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor);
        expect(decryptedSymmetricKey, '');
        expect(remotePLookupRequestCount, 0);
        expect(remoteLLookupRequestCount, 1); // lookup 'my' copy on atServer

        // 2a. atServer unavailable when saving new key to atServer?
        //    => Exception; should not be in remote nor in local
        remoteSecondaryAvailable = false;
        try {
          await ske.createMyCopyOfSharedSymmetricKey(fooBarForVictor);
        } catch (e, st) {
          if (e is! SecondaryConnectException) {
            print('Unexpected exception $e, $st');
          }
          expect(e is SecondaryConnectException, true);
        }
        expect(remoteLLookupRequestCount, 1); // still the same
        expect(remoteDeleteRequestCount,
            1); // a delete attempt for 'their' copy in atServer
        expect(remoteUpdateRequestCount,
            0); // 0 because we try the delete of 'their' copy first, and remote was 'unavailable'
        expect(localStore.isKeyExists(myCopyVicSymKeyName), false);
        expect(remoteUpdatedMap[myCopyVicSymKeyName], null);

        // 2b. atServer available? new key should be created in remote and in local
        remoteSecondaryAvailable = true;
        await ske.createMyCopyOfSharedSymmetricKey(fooBarForVictor);
        expect(remoteLLookupRequestCount, 1); // still the same
        expect(remoteDeleteRequestCount,
            2); // another delete attempt for 'their' copy in atServer
        expect(remoteUpdateRequestCount, 1); // update 'our' copy to atServer
        expect(remoteDeletedSet.contains(vicsCopySymKeyName), true);
        expect(remoteUpdatedMap[myCopyVicSymKeyName] != null, true);
        expect(localStore.isKeyExists(myCopyVicSymKeyName), true);
      });

      // 3. My copy not found in local, found in atServer => save to local
      // Also, when 'my copy' is not found locally, we also delete any local copy of 'their copy'
      test('no my copy locally, but found on atServer, so should store locally',
          () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        expect(localStore.isKeyExists(myCopyVicSymKeyName), false);
        await atClient
            .getLocalSecondary()!
            .putValue(vicsCopySymKeyName, 'dummy symmetric key');
        expect(localStore.isKeyExists(vicsCopySymKeyName), true);
        remoteLLookupMap[myCopyVicSymKeyName] = myEncryptedVicSymKey;

        var decryptedSymmetricKey =
            await ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor);
        expect(decryptedSymmetricKey, victorSymKey);
        expect(localStore.isKeyExists(myCopyVicSymKeyName), true);
        expect(localStore.isKeyExists(vicsCopySymKeyName), false);
      });

      // 4. My copy found locally, make no request to atServer
      test('my copy found locally, no LLookup request to atServer', () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        await atClient
            .getLocalSecondary()!
            .putValue(myCopyVicSymKeyName, myEncryptedVicSymKey);
        expect(localStore.isKeyExists(myCopyVicSymKeyName), true);

        var decryptedSymmetricKey =
            await ske.getMyCopyOfSharedSymmetricKey(fooBarForVictor);
        expect(decryptedSymmetricKey, victorSymKey);
        expect(remoteLLookupRequestCount, 0);
        expect(remotePLookupRequestCount, 0);
      });

      // 5. Their copy not found local, atServer unavailable => exception
      test('their copy not found locally, remote unavailable, exception',
          () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        expect(localStore.isKeyExists(vicsCopySymKeyName), false);

        remoteSecondaryAvailable = false;
        try {
          await ske.verifyTheirCopyOfSharedSymmetricKey(
              fooBarForVictor, victorSymKey);
        } catch (e) {
          expect(e is SecondaryConnectException, true);
        }
        expect(remoteLLookupRequestCount, 1);
      });

      // 6. Their copy not found local, not found in atServer => save to atServer
      //   then to local
      test('their copy not found locally nor remotely, save remote then local',
          () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        expect(remoteUpdatedMap.containsKey(vicsCopySymKeyName), false);
        expect(localStore.isKeyExists(vicsCopySymKeyName), false);

        var encryptedForVictor = await ske.verifyTheirCopyOfSharedSymmetricKey(
            fooBarForVictor, victorSymKey);
        expect(remoteUpdatedMap[vicsCopySymKeyName], encryptedForVictor);
        expect(localStore.isKeyExists(vicsCopySymKeyName), true);
      });

      // 7. Their copy not found local, found in atServer => save to local
      test(
          'their copy not found locally but found remotely, save remote value to local',
          () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        remoteLLookupMap[vicsCopySymKeyName] =
            'encrypted symmetric key copy for victor';
        expect(localStore.isKeyExists(vicsCopySymKeyName), false);

        await ske.verifyTheirCopyOfSharedSymmetricKey(
            fooBarForVictor, victorSymKey);
        expect(remoteLLookupRequestCount, 1);
        expect(remoteUpdateRequestCount, 0);
        expect(localStore.isKeyExists(vicsCopySymKeyName), true);
        var valueCopiedToLocalStore =
            (await localStore.get(vicsCopySymKeyName)).data;
        expect(
            valueCopiedToLocalStore, 'encrypted symmetric key copy for victor');
      });
      // 8. Their copy found local, make no request to atServer
      test('their copy found locally, make no request to atServer', () async {
        SharedKeyEncryption ske = SharedKeyEncryption(atClient);
        await atClient.getLocalSecondary()!.putValue(
            vicsCopySymKeyName, 'encrypted symmetric key copy for victor');

        remoteSecondaryAvailable = true;
        await ske.verifyTheirCopyOfSharedSymmetricKey(
            fooBarForVictor, victorSymKey);
        expect(remotePLookupRequestCount, 0);
        expect(remoteLLookupRequestCount, 0);
        expect(remoteUpdateRequestCount, 0);
        expect(remoteDeleteRequestCount, 0);

        remoteSecondaryAvailable = false;
        await ske.verifyTheirCopyOfSharedSymmetricKey(
            fooBarForVictor, victorSymKey);

        // And let's just double check nothing else weird has happened
        var valueInLocalStore = (await localStore.get(vicsCopySymKeyName)).data;
        expect(valueInLocalStore, 'encrypted symmetric key copy for victor');
      });
    });
  });
}
