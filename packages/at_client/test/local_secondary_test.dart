import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'test_utils/test_utils.dart';

class MockSecondaryKeyStore extends Mock implements SecondaryKeyStore {
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
  List<String> getKeys({String? regex}) {
    if (regex != null) {
      RegExp re = RegExp(regex);
      return keysInKeyStore.where((key) {
        return key.contains(re);
      }).toList();
    } else {
      return keysInKeyStore.toList();
    }
  }
}

class MockAtClientImpl extends Mock implements AtClientImpl {}

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
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final pkamPrivateKey = RSAKeypair.fromRandom().privateKey.toString();
      await localSecondary.putValue(
          AtConstants.atPkamPrivateKey, pkamPrivateKey);
      expect(await localSecondary.getPrivateKey(), pkamPrivateKey);
    });

    test('test get public key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final pkamPublicKey = RSAKeypair.fromRandom().publicKey.toString();
      await localSecondary.putValue(AtConstants.atPkamPublicKey, pkamPublicKey);
      expect(await localSecondary.getPublicKey(), pkamPublicKey);
    });

    test('test get encryption private key', () async {
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
          AtConstants.atEncryptionPrivateKey, encryptionPrivateKey);
      expect(
          await localSecondary.getEncryptionPrivateKey(), encryptionPrivateKey);
    });

    test('test get encryption public key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final encryptionPublicKey = RSAKeypair.fromRandom().publicKey.toString();
      await localSecondary.putValue(
          '${AtConstants.atEncryptionPublicKey}$atSign', encryptionPublicKey);
      expect(await localSecondary.getEncryptionPublicKey(atSign),
          encryptionPublicKey);
    });

    test('test get self encryption key', () async {
      final atClientManager = AtClientManager(atSign);
      final preference = AtClientPreference()
        ..syncRegex = '.wavi'
        ..hiveStoragePath = 'test/hive';
      AtClient atClient = await AtClientImpl.create(atSign, 'wavi', preference,
          atClientManager: atClientManager);
      final localSecondary = LocalSecondary(atClient);
      final selfEncryptionKey = EncryptionUtil.generateAESKey();
      await localSecondary.putValue(
          AtConstants.atEncryptionSelfKey, selfEncryptionKey);
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
        ..hiveStoragePath = 'test/hive';
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
        ..hiveStoragePath = 'test/hive';
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
        ..hiveStoragePath = 'test/hive';
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
        ..hiveStoragePath = 'test/hive';
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
        ..hiveStoragePath = 'test/hive';
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
        ..hiveStoragePath = 'test/hive';
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

  group('A group of tests to validate getKeys and getAtKeys', () {
    late SecondaryKeyStore mockSecondaryKeyStore;
    late LocalSecondary localSecondary;
    late AtClient atClient;
    final String namespace = 'validate_get_keys';
    final preference = AtClientPreference()
      ..syncRegex = '.$namespace'
      ..hiveStoragePath =
          '*&@should not be used by these tests, we will mock local storage'
      ..isLocalStoreRequired = true;

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
}

Future<void> setupLocalStorage(String storageDir, String atSign) async {
  var commitLogInstance = await AtCommitLogManagerImpl.getInstance()
      .getCommitLog(atSign, commitLogPath: storageDir);
  var persistenceManager = SecondaryPersistenceStoreFactory.getInstance()
      .getSecondaryPersistenceStore(atSign)!;
  await persistenceManager.getHivePersistenceManager()!.init(storageDir);
  persistenceManager.getSecondaryKeyStore()!.commitLog = commitLogInstance;
}

Future<void> tearDownLocalStorage(storageDir) async {
  try {
    var isExists = await Directory(storageDir).exists();
    if (isExists) {
      Directory(storageDir).deleteSync(recursive: true);
    }
  } catch (e, st) {
    print('local_secondary_test.dart: exception / error in tearDown: $e, $st');
  }
}
