import 'dart:convert';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:crypton/crypton.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:at_lookup/at_lookup.dart' show AtLookUpException;

import 'test_utils/mocks.dart';
import 'test_utils/test_utils.dart';

class MockSecondaryKeyStore extends Mock
    implements AtKeyValueStore<String, AtData, AtMetaData?> {
  static const String hiddenKey1 = 'public:__location.wavi@alice';
  static const String hiddenKey2 = '_profilePic.wavi@alice';
  static const String nonHiddenKey1 = 'public:nickname.wavi@alice';
  static const String nonHiddenKey2 = 'some.self.key.wavi@alice';
  static const String otherWaviHiddenKey = 'public:__location.other_wavi@alice';
  static const String waviOtherHiddenKey = 'public:__location.wavi_other@alice';
  static const String otherWaviOtherHiddenKey =
      'public:__location.other_wavi_other@alice';
  static const String otherWaviNonHiddenKey =
      'public:nickname.other_wavi@alice';
  static const String waviOtherNonHiddenKey =
      'public:nickname.wavi_other@alice';
  static const String otherWaviOtherNonHiddenKey =
      'public:nickname.other_wavi_other@alice';
  static const List<String> keysInKeyStore = [
    nonHiddenKey1,
    hiddenKey1,
    otherWaviHiddenKey,
    nonHiddenKey2,
    hiddenKey2,
    otherWaviNonHiddenKey,
    waviOtherHiddenKey,
    otherWaviOtherHiddenKey,
    waviOtherNonHiddenKey,
    otherWaviOtherNonHiddenKey
  ];

  @override
  Future<Stream<String>> getKeys({String? regex}) async {
    if (regex != null) {
      RegExp re = RegExp(regex);
      return Stream.fromIterable(
          keysInKeyStore.where((key) => key.contains(re)));
    }
    return Stream.fromIterable(keysInKeyStore);
  }

  // The scan tests only exercise getKeys; reads (used incidentally by
  // AtChops bootstrap during AtClientImpl.create) resolve to null.
  @override
  Future<AtData?> get(String key) async => null;

  @override
  Future<AtMetaData?> getMeta(String key) async => null;

  // No TTL/TTB entries — the expiry/availability timer surfaces the
  // AtClient bootstrap consults are all no-ops.
  @override
  Future<DateTime?> nextExpiresAt() async => null;

  @override
  Future<DateTime?> nextAvailableAt({DateTime? asOf}) async => null;

  @override
  Future<Stream<String>> peekNewlyAvailable(
          {required DateTime since, DateTime? asOf, int? limit}) async =>
      const Stream.empty();
}

class MockAtClientImpl extends Mock implements AtClientImpl {
  @override
  SigningAlgoType get signingAlgoType => SigningAlgoType.rsa2048;
}

void main() {
  var storageDir = '${Directory.current.path}/test/hive';

  final String atSign = '@alice';

  group('A group of local secondary get keys test', () {
    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      await setupLocalStorage(storageDir, atSign);
    });
    tearDown(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      await tearDownLocalStorage(storageDir);
    });

    test('test get private key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final pkamPrivateKey = RSAKeypair.fromRandom().privateKey.toString();
      final success = await localSecondary.putValue(
          AtConstants.atPkamPrivateKey, pkamPrivateKey);
      expect(success, true);
      expect(await localSecondary.getPkamPrivateKey(), pkamPrivateKey);
    });

    test('test get public key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final pkamPublicKey = RSAKeypair.fromRandom().publicKey.toString();
      final success = await localSecondary.putValue(
          AtConstants.atPkamPublicKey, pkamPublicKey);
      expect(success, true);
      expect(await localSecondary.getPkamPublicKey(), pkamPublicKey);
    });

    test('test get encryption private key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final encryptionPrivateKey =
          RSAKeypair.fromRandom().privateKey.toString();
      final success = await localSecondary.putValue(
          AtConstants.atEncryptionPrivateKey, encryptionPrivateKey);
      expect(success, true);
      expect(
          await localSecondary.getEncryptionPrivateKey(), encryptionPrivateKey);
    });

    test('test get encryption public key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final encryptionPublicKey = RSAKeypair.fromRandom().publicKey.toString();
      final success = await localSecondary.putValue(
          '${AtConstants.atEncryptionPublicKey}$atSign', encryptionPublicKey);
      expect(success, true);
      expect(await localSecondary.getEncryptionPublicKey(atSign),
          encryptionPublicKey);
    });

    test('test get self encryption key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final selfEncryptionKey = EncryptionUtil.generateAESKey();
      final success = await localSecondary.putValue(
          AtConstants.atEncryptionSelfKey, selfEncryptionKey);
      expect(success, true);
      expect(await localSecondary.getEncryptionSelfKey(), selfEncryptionKey);
    });
  });

  group('A group of local secondary execute verb tests', () {
    setUp(() async => await setupLocalStorage(storageDir, atSign));
    tearDown(() async => await tearDownLocalStorage(storageDir));

    test('test update verb builder', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'alice@gmail.com';
      final executeResult =
          await localSecondary.executeVerb(verbBuilder, sync: false);
      expect(executeResult, isNotNull);
      expect(executeResult!.startsWith('data:'), true);
    });

    test('test update verb builder max key length check', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      var key = TestUtils.createRandomString(250);
      final verbBuilder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = key
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'alice@gmail.com';
      expect(
          () async =>
              await localSecondary.executeVerb(verbBuilder, sync: false),
          throwsA(predicate((dynamic e) =>
              e is DataStoreException &&
              e.message ==
                  'key length ${'public:'.length + key.length + atSign.length} is greater than max allowed 248 chars')));
    });

    test('test update verb builder max key length check for cached key',
        () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      var key = TestUtils.createRandomString(250);
      final verbBuilder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = key
          ..sharedBy = atSign
          ..metadata = (Metadata()
            ..isCached = true
            ..isPublic = true))
        ..value = 'alice@gmail.com';
      expect(
          () async =>
              await localSecondary.executeVerb(verbBuilder, sync: false),
          throwsA(predicate((dynamic e) =>
              e is DataStoreException &&
              e.message ==
                  'key length ${'cached:'.length + 'public:'.length + key.length + atSign.length} is greater than max allowed 255 chars')));
    });

    test('test llookup verb builder', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'alice@gmail.com';
      await localSecondary.executeVerb(verbBuilder, sync: false);
      final llookupVerbBuilder = LLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true));
      final llookupResult =
          await localSecondary.executeVerb(llookupVerbBuilder, sync: false);
      expect(llookupResult, 'data:alice@gmail.com');
    });

    test('test delete verb builder', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'alice@gmail.com';
      await localSecondary.executeVerb(verbBuilder, sync: false);
      final deleteVerbBuilder = DeleteVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true));
      await localSecondary.executeVerb(deleteVerbBuilder, sync: false);
      final llookupVerbBuilder = LLookupVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true));
      expect(localSecondary.executeVerb(llookupVerbBuilder, sync: false),
          throwsA(isA<KeyNotFoundException>()));
    });

    test('test scan verb builder', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final verbBuilder_1 = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'alice@gmail.com';
      await localSecondary.executeVerb(verbBuilder_1, sync: false);
      final verbBuilder_2 = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'phone'
          ..sharedBy = atSign)
        ..value = '+101-202-303';
      await localSecondary.executeVerb(verbBuilder_2, sync: false);
      final scanVerbBuilder = ScanVerbBuilder();
      final scanResult =
          await localSecondary.executeVerb(scanVerbBuilder, sync: false);
      final scanJson = jsonDecode(scanResult!);
      print(scanJson);
      expect(scanJson.contains('phone$atSign'), true);
      expect(scanJson.contains('public:email$atSign'), true);
    });
  });

  group('writesInProgress tracker', () {
    setUp(() async => await setupLocalStorage(storageDir, atSign));
    tearDown(() async => await tearDownLocalStorage(storageDir));

    /// Builds a fresh LocalSecondary against the test Hive store. Each
    /// test gets its own AtClient instance (atClientInstanceMap is
    /// cleared in the outer setUp).
    Future<LocalSecondary> buildLocalSecondary() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive'
        ..commitLogPath = 'test/hive/commit';
      final atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      return LocalSecondary(atClient);
    }

    UpdateVerbBuilder updateBuilderFor(String keyName) => UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = keyName
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true))
      ..value = 'v';

    test('starts empty', () async {
      final localSecondary = await buildLocalSecondary();
      expect(localSecondary.writesInProgressForTest, isEmpty);
    });

    test('cleared after a successful update', () async {
      final localSecondary = await buildLocalSecondary();
      await localSecondary.executeVerb(updateBuilderFor('email'), sync: false);
      expect(localSecondary.writesInProgressForTest, isEmpty);
      expect(localSecondary.isWriteInProgress('public:email$atSign'), false);
    });

    test('cleared after an update that throws (finally branch fires)',
        () async {
      // Trigger the max-key-length DataStoreException path inside
      // _update to exercise the catch-then-rethrow; the in-progress
      // tracker must still empty out in `finally`.
      final localSecondary = await buildLocalSecondary();
      final tooLongKey = TestUtils.createRandomString(250);
      final builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = tooLongKey
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true))
        ..value = 'v';
      await expectLater(
          () async => await localSecondary.executeVerb(builder, sync: false),
          throwsA(isA<DataStoreException>()));
      expect(localSecondary.writesInProgressForTest, isEmpty);
    });

    test('cleared after a delete', () async {
      final localSecondary = await buildLocalSecondary();
      await localSecondary.executeVerb(updateBuilderFor('email'), sync: false);
      final deleteBuilder = DeleteVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'email'
          ..sharedBy = atSign
          ..metadata = (Metadata()..isPublic = true));
      await localSecondary.executeVerb(deleteBuilder, sync: false);
      expect(localSecondary.writesInProgressForTest, isEmpty);
    });

    test('snapshot getter returns an unmodifiable view', () async {
      final localSecondary = await buildLocalSecondary();
      final snapshot = localSecondary.writesInProgressForTest;
      expect(() => snapshot.add('xxx'), throwsUnsupportedError);
    });
  });

  group('A group of tests to validate getKeys and getAtKeys', () {
    late AtKeyValueStore<String, AtData, AtMetaData?> mockSecondaryKeyStore;
    late LocalSecondary localSecondary;
    late AtClient atClient;
    final String namespace = 'validate_get_keys';
    final preference = AtClientPreference()
      ..syncRegex = '.$namespace'
      ..hiveStoragePath =
          '*&@should not be used by these tests, we will mock local storage'
      ..commitLogPath = 'test/hive/commit';
    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);

      mockSecondaryKeyStore = MockSecondaryKeyStore();
      atClient = await AtClientImpl.create(atSign, namespace, preference,
          atClientManager: AtClientManager(atSign),
          localSecondaryKeyStore: mockSecondaryKeyStore);
      localSecondary =
          LocalSecondary(atClient, keyStore: mockSecondaryKeyStore);
    });

    tearDown(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
    });

    test('LocalSecondary scan, showHiddenKeys:true, regex:<actualDot>wavi@',
        () async {
      var response = await localSecondary.executeVerb(ScanVerbBuilder()
        ..showHiddenKeys = true
        ..regex = '\\.wavi@');
      expect(response?.contains(MockSecondaryKeyStore.hiddenKey1), true);
      expect(response?.contains(MockSecondaryKeyStore.hiddenKey2), true);
      expect(response?.contains(MockSecondaryKeyStore.nonHiddenKey1), true);
      expect(response?.contains(MockSecondaryKeyStore.nonHiddenKey2), true);
      expect(
          response?.contains(MockSecondaryKeyStore.otherWaviHiddenKey), false);
      expect(
          response?.contains(MockSecondaryKeyStore.waviOtherHiddenKey), false);
      expect(response?.contains(MockSecondaryKeyStore.otherWaviOtherHiddenKey),
          false);
      expect(response?.contains(MockSecondaryKeyStore.otherWaviNonHiddenKey),
          false);
      expect(response?.contains(MockSecondaryKeyStore.waviOtherNonHiddenKey),
          false);
      expect(
          response?.contains(MockSecondaryKeyStore.otherWaviOtherNonHiddenKey),
          false);
    });

    test('getKeys, showHiddenKeys:true, regex:<actualDot>wavi@', () async {
      List<String> response =
          await atClient.getKeys(showHiddenKeys: true, regex: '\\.wavi@');
      expect(response.contains(MockSecondaryKeyStore.hiddenKey1), true);
      expect(response.contains(MockSecondaryKeyStore.hiddenKey2), true);
      expect(response.contains(MockSecondaryKeyStore.nonHiddenKey1), true);
      expect(response.contains(MockSecondaryKeyStore.nonHiddenKey2), true);
      expect(
          response.contains(MockSecondaryKeyStore.otherWaviHiddenKey), false);
      expect(
          response.contains(MockSecondaryKeyStore.waviOtherHiddenKey), false);
      expect(response.contains(MockSecondaryKeyStore.otherWaviOtherHiddenKey),
          false);
      expect(response.contains(MockSecondaryKeyStore.otherWaviNonHiddenKey),
          false);
      expect(response.contains(MockSecondaryKeyStore.waviOtherNonHiddenKey),
          false);
      expect(
          response.contains(MockSecondaryKeyStore.otherWaviOtherNonHiddenKey),
          false);
    });

    // We'll test getAtKeys (which calls getKeys, which calls LocalSecondary scan)
    // with multiple regex variants to verify regex is being processed correctly
    test('getAtKeys, showHiddenKeys:true, regex:<actualDot>wavi@', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: true, regex: '\\.wavi@');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          true);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          false);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          false);
    });

    test('getAtKeys, showHiddenKeys:true, regex:<regexDot>wavi@', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: true, regex: '.wavi@');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          true);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          false);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          false);
    });

    test('getAtKeys, showHiddenKeys:true, regex:<actualDot>wavi', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: true, regex: '\\.wavi');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          true);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          true);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          false);
    });

    test('getAtKeys, showHiddenKeys:true, regex:<regexDot>wavi', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: true, regex: '.wavi');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          true);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          true);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          true);
    });

    test('LocalSecondary scan, showHiddenKeys:false, regex:<actualDot>wavi@',
        () async {
      var response = await localSecondary.executeVerb(ScanVerbBuilder()
        ..showHiddenKeys = false
        ..regex = '\\.wavi@');
      expect(response?.contains(MockSecondaryKeyStore.hiddenKey1), false);
      expect(response?.contains(MockSecondaryKeyStore.hiddenKey2), false);
      expect(response?.contains(MockSecondaryKeyStore.nonHiddenKey1), true);
      expect(response?.contains(MockSecondaryKeyStore.nonHiddenKey2), true);
      expect(
          response?.contains(MockSecondaryKeyStore.otherWaviHiddenKey), false);
      expect(
          response?.contains(MockSecondaryKeyStore.waviOtherHiddenKey), false);
      expect(response?.contains(MockSecondaryKeyStore.otherWaviOtherHiddenKey),
          false);
      expect(response?.contains(MockSecondaryKeyStore.otherWaviNonHiddenKey),
          false);
      expect(response?.contains(MockSecondaryKeyStore.waviOtherNonHiddenKey),
          false);
      expect(
          response?.contains(MockSecondaryKeyStore.otherWaviOtherNonHiddenKey),
          false);
    });

    test('getKeys, showHiddenKeys:false, regex:<actualDot>wavi@', () async {
      List<String> response =
          await atClient.getKeys(showHiddenKeys: false, regex: '\\.wavi@');
      expect(response.contains(MockSecondaryKeyStore.hiddenKey1), false);
      expect(response.contains(MockSecondaryKeyStore.hiddenKey2), false);
      expect(response.contains(MockSecondaryKeyStore.nonHiddenKey1), true);
      expect(response.contains(MockSecondaryKeyStore.nonHiddenKey2), true);
      expect(
          response.contains(MockSecondaryKeyStore.otherWaviHiddenKey), false);
      expect(
          response.contains(MockSecondaryKeyStore.waviOtherHiddenKey), false);
      expect(response.contains(MockSecondaryKeyStore.otherWaviOtherHiddenKey),
          false);
      expect(response.contains(MockSecondaryKeyStore.otherWaviNonHiddenKey),
          false);
      expect(response.contains(MockSecondaryKeyStore.waviOtherNonHiddenKey),
          false);
      expect(
          response.contains(MockSecondaryKeyStore.otherWaviOtherNonHiddenKey),
          false);
    });

    test('getAtKeys, showHiddenKeys:false, regex:<actualDot>wavi@', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: false, regex: '\\.wavi@');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          false);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          false);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          false);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          false);
    });

    test('getAtKeys, showHiddenKeys:false, regex:<regexDot>wavi@', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: false, regex: '.wavi@');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          false);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          false);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          false);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          false);
    });

    test('getAtKeys, showHiddenKeys:false, regex:<actualDot>wavi', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: false, regex: '\\.wavi');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          false);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          false);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          true);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          false);
    });

    test('getAtKeys, showHiddenKeys:false, regex:<regexDot>wavi', () async {
      List<AtKey> response =
          await atClient.getAtKeys(showHiddenKeys: false, regex: '.wavi');
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey1)),
          false);
      expect(
          response.contains(AtKey.fromString(MockSecondaryKeyStore.hiddenKey2)),
          false);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey1)),
          true);
      expect(
          response
              .contains(AtKey.fromString(MockSecondaryKeyStore.nonHiddenKey2)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviOtherHiddenKey)),
          false);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.otherWaviNonHiddenKey)),
          true);
      expect(
          response.contains(
              AtKey.fromString(MockSecondaryKeyStore.waviOtherNonHiddenKey)),
          true);
      expect(
          response.contains(AtKey.fromString(
              MockSecondaryKeyStore.otherWaviOtherNonHiddenKey)),
          true);
    });
  });

  /// The enrollment record is fetched from the atServer on first use. There is
  /// no local cache: one used to be written here and could never be read back,
  /// because the read looked for `local:<enrollmentId><atSign>` and the write
  /// went to the atServer's own `<enrollmentId>.new.enrollments.__manage`
  /// naming.
  group('fetching the enrollment record', () {
    late MockRemoteSecondary remote;

    // ⚠️ The instance map is keyed by atSign, so without this eviction
    // `AtClientImpl.create` hands back a client built by an earlier group —
    // with that group's remote secondary, and with `enrollment` already
    // memoised. Every stub below would then be measuring the wrong object.
    setUp(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      await setupLocalStorage(storageDir, atSign);
    });
    tearDown(() async {
      AtClientImpl.atClientInstanceMap.remove(atSign);
      await tearDownLocalStorage(storageDir);
    });

    Future<AtClient> client({String? enrollmentId}) async {
      remote = MockRemoteSecondary();
      final c = await AtClientImpl.create(
          atSign,
          'wavi',
          AtClientPreference()
            ..hiveStoragePath = 'test/hive'
            ..commitLogPath = 'test/hive/commit',
          remoteSecondary: remote);
      c.enrollmentId = enrollmentId;
      return c;
    }

    test('a client with no enrollment id has no record to fetch', () async {
      final c = await client();
      expect(await c.getLocalSecondary()!.getEnrollmentDetails(), isNull);
      verifyNever(() => remote.executeCommand(any(), auth: any(named: 'auth')));
    });

    test('the fetched record is parsed, and fetched only once', () async {
      final c = await client(enrollmentId: 'e-1');
      when(() =>
          remote.executeCommand('enroll:fetch:{"enrollmentId":"e-1"}\n',
              auth: true)).thenAnswer((_) async => 'data:${jsonEncode({
                'appName': 'buzz',
                'deviceName': 'pixel',
                'namespace': {'buzz': 'rw'},
              })}');

      final first = await c.getLocalSecondary()!.getEnrollmentDetails();
      expect(first!.appName, 'buzz');
      expect(first.namespace, {'buzz': 'rw'});

      await c.getLocalSecondary()!.getEnrollmentDetails();
      verify(() => remote.executeCommand(any(), auth: true)).called(1);
    });

    test('a failed fetch names the enrollment and the cause', () async {
      final c = await client(enrollmentId: 'e-2');
      when(() => remote.executeCommand(any(), auth: true))
          .thenThrow(AtLookUpException('AT0014', 'the atServer said no'));

      // Before this, both catch arms logged at `finer` and fell through to a
      // `!` on the null result, so an unreachable atServer surfaced as "Null
      // check operator used on a null value" from a line naming neither the
      // enrollment nor the fetch — with the exception that explains it
      // discarded at a level nobody runs at.
      await expectLater(
          () => c.getLocalSecondary()!.getEnrollmentDetails(),
          throwsA(isA<AtKeyNotFoundException>()
              .having((e) => e.message, 'message', contains('e-2'))
              .having((e) => e.message, 'message',
                  contains('the atServer said no'))));
    });
  });
}

// The AtClient owns its commit-log-free persistence bundle (created
// by `AtClientImpl.create`, since `isLocalStoreRequired` defaults to
// true). Tests build their own client, so setup only needs to evict
// any cached instance so storage is reopened fresh.
Future<void> setupLocalStorage(String storageDir, String atSign) async {
  AtClientImpl.atClientInstanceMap.remove(atSign);
}

Future<void> tearDownLocalStorage(String storageDir) async {
  try {
    // Close every Hive box BEFORE deleting storage (open file handles).
    //
    // BOTH registries, and both are needed. `Hive.close()` reaches only the
    // package-global instance; the keystore's own boxes live on a per-path
    // instance (at_persistence_secondary_server's `HiveInstances`), so
    // closing just the global leaves them open over the directory deleted
    // below. The next test then reopens the cached box and reads the previous
    // test's values back — no error, just the wrong data.
    await HiveInstances.closeAll();
    await Hive.close();

    var isExists = await Directory(storageDir).exists();
    if (isExists) {
      Directory(storageDir).deleteSync(recursive: true);
    }
  } catch (e, st) {
    print('local_secondary_test.dart: exception / error in tearDown: $e, $st');
  }
}
