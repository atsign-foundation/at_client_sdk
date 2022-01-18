import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';

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
        ..atKey = 'phone'
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
        ..atKey = 'phone'
        ..sharedBy = atSign;
      await localSecondary.executeVerb(verbBuilder, sync: false);
      final llookupVerbBuilder = LLookupVerbBuilder()
        ..atKey = 'public:phone'
        ..sharedBy = atSign;
      final llookupResult =
          await localSecondary.executeVerb(llookupVerbBuilder, sync: false);
      expect(llookupResult, 'alice@gmail.com');
    });
  });
  try {
    tearDown(() async => await tearDownFunc(storageDir));
  } on Exception catch (e) {
    print('error in tear down:${e.toString()}');
  }
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
  var isExists = await Directory(storageDir).exists();
  if (isExists) {
    Directory(storageDir).deleteSync(recursive: true);
  }
}
