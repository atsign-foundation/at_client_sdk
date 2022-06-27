import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {
  @override
  List<String> getKeys({String? regex}) {
    return ['public:__location.wavi@alice', '_profilePic.wavi@alice'];
  }
}

class MockAtClientImpl extends Mock implements AtClientImpl {}

void main() {
  var storageDir = Directory.current.path + '/test/hive';
  setUp(() async => await setUpFunc(storageDir));
  group('A group of local secondary get keys test', () {
    test('test get private key', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final pkamPrivateKey = RSAKeypair.fromRandom().privateKey.toString();
      await localSecondary.putValue(AT_PKAM_PRIVATE_KEY, pkamPrivateKey);
      expect(await localSecondary.getPrivateKey(), pkamPrivateKey);
    });
    test('test get public key', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final pkamPublicKey = RSAKeypair.fromRandom().publicKey.toString();
      await localSecondary.putValue(AT_PKAM_PUBLIC_KEY, pkamPublicKey);
      expect(await localSecondary.getPublicKey(), pkamPublicKey);
    });
    test('test get encryption private key', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final encryptionPrivateKey =
          RSAKeypair.fromRandom().privateKey.toString();
      await localSecondary.putValue(
          AT_ENCRYPTION_PRIVATE_KEY, encryptionPrivateKey);
      expect(
          await localSecondary.getEncryptionPrivateKey(), encryptionPrivateKey);
    });
    test('test get encryption public key', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final encryptionPublicKey = RSAKeypair.fromRandom().publicKey.toString();
      await localSecondary.putValue(
          '$AT_ENCRYPTION_PUBLIC_KEY$atSign', encryptionPublicKey);
      expect(await localSecondary.getEncryptionPublicKey(atSign),
          encryptionPublicKey);
    });
    test('test get self encryption key', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final selfEncryptionKey = EncryptionUtil.generateAESKey();
      await localSecondary.putValue(AT_ENCRYPTION_SELF_KEY, selfEncryptionKey);
      expect(await localSecondary.getEncryptionSelfKey(), selfEncryptionKey);
    });
    try {
      tearDown(() async => await tearDownFunc(storageDir));
    } on Exception catch (e) {
      print('error in tear down:${e.toString()}');
    }
  });
  group('A group of local secondary execute verb tests', () {
    test('test update verb builder', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder = UpdateVerbBuilder()
        ..isPublic = true
        ..value = 'alice@gmail.com'
        ..atKey = 'email'
        ..sharedBy = '@alice';
      final executeResult =
          await localSecondary.executeVerb(verbBuilder, sync: false);
      expect(executeResult, isNotNull);
      expect(executeResult!.startsWith('data:'), true);
    });
    test('test llookup verb builder', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder = UpdateVerbBuilder()
        ..isPublic = true
        ..value = 'alice@gmail.com'
        ..atKey = 'email'
        ..sharedBy = atSign;
      await localSecondary.executeVerb(verbBuilder, sync: false);
      final llookupVerbBuilder = LLookupVerbBuilder()
        ..atKey = 'public:email'
        ..sharedBy = atSign;
      final llookupResult =
          await localSecondary.executeVerb(llookupVerbBuilder, sync: false);
      expect(llookupResult, 'data:alice@gmail.com');
    });
    test('test delete verb builder', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder = UpdateVerbBuilder()
        ..isPublic = true
        ..value = 'alice@gmail.com'
        ..atKey = 'email'
        ..sharedBy = atSign;
      await localSecondary.executeVerb(verbBuilder, sync: false);
      final deleteVerbBuilder = DeleteVerbBuilder()
        ..atKey = 'public:email'
        ..sharedBy = atSign;
      await localSecondary.executeVerb(deleteVerbBuilder, sync: false);
      final llookupVerbBuilder = LLookupVerbBuilder()
        ..atKey = 'public:email'
        ..sharedBy = atSign;
      expect(localSecondary.executeVerb(llookupVerbBuilder, sync: false),
          throwsA(isA<KeyNotFoundException>()));
    });
    test('test scan verb builder', () async {
      final atSign = '@alice';
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder_1 = UpdateVerbBuilder()
        ..isPublic = true
        ..value = 'alice@gmail.com'
        ..atKey = 'email'
        ..sharedBy = atSign;
      await localSecondary.executeVerb(verbBuilder_1, sync: false);
      final verbBuilder_2 = UpdateVerbBuilder()
        ..value = '+101-202-303'
        ..atKey = 'phone'
        ..sharedBy = atSign;
      await localSecondary.executeVerb(verbBuilder_2, sync: false);
      final scanVerbBuilder = ScanVerbBuilder();
      final scanResult =
          await localSecondary.executeVerb(scanVerbBuilder, sync: false);
      final scanJson = jsonDecode(scanResult!);
      print(scanJson);
      expect(scanJson.contains('phone@alice'), true);
      expect(scanJson.contains('public:email@alice'), true);
    });
  });
  try {
    tearDown(() async => await tearDownFunc(storageDir));
  } on Exception catch (e) {
    print('error in tear down:${e.toString()}');
  }

  group('A group of tests to validate getKeys', () {
    test('A test to validate getKeys when showHidden is set to true', () async {
      AtClientImpl mockAtClientImpl = MockAtClientImpl();
      SecondaryKeyStore mockSecondaryKeyStore = MockSecondaryKeyStore();
      LocalSecondary localSecondary = LocalSecondary(mockAtClientImpl);
      localSecondary.keyStore = mockSecondaryKeyStore;
      var response = await localSecondary
          .executeVerb(ScanVerbBuilder()..showHiddenKeys = true);
      expect(response?.contains('public:__location.wavi@alice'), true);
      expect(response?.contains('_profilePic.wavi@alice'), true);
    });

    test('A test to validate getKeys when showHidden is set to true', () async {
      AtClientImpl mockAtClientImpl = MockAtClientImpl();
      SecondaryKeyStore mockSecondaryKeyStore = MockSecondaryKeyStore();
      LocalSecondary localSecondary = LocalSecondary(mockAtClientImpl);
      localSecondary.keyStore = mockSecondaryKeyStore;
      var response = await localSecondary
          .executeVerb(ScanVerbBuilder()..showHiddenKeys = false);
      expect(response?.contains('public:__location.wavi@alice'), false);
      expect(response?.contains('_profilePic.wavi@alice'), false);
    });
  });
}

Future<void> setUpFunc(storageDir) async {
  var commitLogInstance = await AtCommitLogManagerImpl.getInstance()
      .getCommitLog('@alice', commitLogPath: storageDir);
  var persistenceManager = SecondaryPersistenceStoreFactory.getInstance()
      .getSecondaryPersistenceStore('@alice')!;
  await persistenceManager.getHivePersistenceManager()!.init(storageDir);
  persistenceManager.getSecondaryKeyStore()!.commitLog = commitLogInstance;
}

Future<void> tearDownFunc(storageDir) async {
  print('***local sec tearDown');
  var isExists = await Directory(storageDir).exists();
  if (isExists) {
    Directory(storageDir).deleteSync(recursive: true);
  }
}
