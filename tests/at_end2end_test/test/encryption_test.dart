import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_end2end_test/utils/test_crypto_scheme.dart';
import 'package:test/test.dart';

void main() {
  late String atSign_1;
  late String atSign_2;
  final namespace = TestConstants.namespace;

  var clearText = 'Some clear text';

  setUpAll(() async {
    atSign_1 = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atSign_2 = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign_1, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign_2, namespace, authType);
  });

  tearDownAll(() {});

  Future<AtClient> getAtClient(String atSign) async {
    AtClient atClient = (await AtClientManager.getInstance().setCurrentAtSign(
            atSign,
            namespace,
            TestPreferences.getInstance().getPreference(atSign)))
        .atClient;

    return atClient;
  }

  String uniqueKeyName(String prefix) {
    return '$prefix.${DateTime.now().microsecondsSinceEpoch}';
  }

  String uniqueSchemeName(String prefix) {
    return '$prefix${DateTime.now().microsecondsSinceEpoch}';
  }

  AtKey sharedKey(String keyName) {
    return (AtKey.shared(keyName, sharedBy: atSign_1)
          ..sharedWith(atSign_2)
          ..timeToLive(TestConstants.oneMinuteMillis))
        .build();
  }

  final PutRequestOptions remotePRO = PutRequestOptions()
    ..useRemoteAtServer = true;
  final GetRequestOptions remoteGRO = GetRequestOptions()
    ..useRemoteAtServer = true;

  group('Group of tests storing shared encryption key in metadata', () {
    test('Test put shared, then get, with IV', () async {
      AtClient atClient_1 = await getAtClient(atSign_1);

      var atKey = (AtKey.shared('test_share.2_0.to.2_0', sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(TestConstants.oneMinuteMillis))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: remotePRO);
      expect(atKey.metadata.ivNonce, isNotNull);

      AtClient atClient_2 = await getAtClient(atSign_2);

      var getResult = await atClient_2.get(atKey, getRequestOptions: remoteGRO);
      expect(getResult.value, clearText);
    });
  });

  group('Group of tests NOT storing shared encryption key in metadata', () {
    PutRequestOptions putOptions = PutRequestOptions()
      ..useRemoteAtServer = true;
    GetRequestOptions getOptions = GetRequestOptions()
      ..bypassCache = true
      ..useRemoteAtServer = true;

    test('Test put shared, then get, with IV', () async {
      AtClient atClient_1 = await getAtClient(atSign_1);

      var atKey = (AtKey.shared('test_share.2_0.to.2_0.no_inlined_key',
              sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(TestConstants.oneMinuteMillis))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: putOptions);
      expect(atKey.metadata.ivNonce, isNotNull);
      // sharedKeyEnc and pubKeyCS are now *always* set
      expect(atKey.metadata.sharedKeyEnc, isNotNull);
      expect(atKey.metadata.pubKeyCS, isNotNull);

      AtClient atClient_2 = await getAtClient(atSign_2);

      var getResult =
          await atClient_2.get(atKey, getRequestOptions: getOptions);
      expect(getResult.value, clearText);
    });
  });

  group('Pluggable encryption / decryption', () {
    GetRequestOptions getOptions = GetRequestOptions()
      ..bypassCache = true
      ..useRemoteAtServer = true;
    test('✓ with custom cryptoscheme', () async {
      final schemeName = uniqueSchemeName('testscheme');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..encryptionScheme = schemeName;
      //step 1. put with app specified scheme
      AtClient ac1 = await getAtClient(atSign_1);
      ac1.atChops!.schemes.register(schemeName, TestCryptoScheme());
      var atKey = sharedKey(uniqueKeyName('test_share.scheme'));
      await ac1.put(atKey, clearText, putRequestOptions: putOptions);

      //step 2. get with the shared atsign
      AtClient ac2 = await getAtClient(atSign_2);
      ac2.atChops!.schemes.register(schemeName, TestCryptoScheme());
      var getResult = await ac2.get(atKey, getRequestOptions: getOptions);
      // see `TestCryptoScheme` for the returning values
      expect(getResult.value, 'twin');
    });
    test('✘ with custom cryptoscheme: fails due to ac2 not having scheme',
        () async {
      final schemeName = uniqueSchemeName('testscheme');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..encryptionScheme = schemeName;
      //step 1. put with app specified scheme
      AtClient ac1 = await getAtClient(atSign_1);
      ac1.atChops!.schemes.register(schemeName, TestCryptoScheme());
      var atKey = sharedKey(uniqueKeyName('test_share.scheme'));
      await ac1.put(atKey, clearText, putRequestOptions: putOptions);

      //step 2. get with the shared atsign, should throw
      AtClient ac2 = await getAtClient(atSign_2);
      expect(
          () async => await ac2.get(atKey, getRequestOptions: getOptions),
          throwsA(
            isA<CryptoSchemeNotRegistered>(),
          ));
    });

    // these tests should fail, I think these are edge cases I haven't considered.
    test('expected failure: custom scheme survives a fresh remote get',
        () async {
      final schemeName = uniqueSchemeName('testscheme');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..encryptionScheme = schemeName;
      AtClient ac1 = await getAtClient(atSign_1);
      ac1.atChops!.schemes.register(schemeName, TestCryptoScheme());
      final keyName = uniqueKeyName('test_share.scheme.fresh_remote');
      await ac1.put(sharedKey(keyName), clearText,
          putRequestOptions: putOptions);

      AtClient ac2 = await getAtClient(atSign_2);
      ac2.atChops!.schemes.register(schemeName, TestCryptoScheme());
      final freshReadKey = sharedKey(keyName);
      var getResult =
          await ac2.get(freshReadKey, getRequestOptions: getOptions);

      expect(getResult.metadata?.appMetadata?.encryptionScheme, schemeName);
      expect(getResult.value, 'twin');
    });

    test('expected failure: custom scheme survives cached local sync',
        () async {
      final schemeName = uniqueSchemeName('testscheme');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..encryptionScheme = schemeName;
      AtClient ac1 = await getAtClient(atSign_1);
      ac1.atChops!.schemes.register(schemeName, TestCryptoScheme());
      final keyName = uniqueKeyName('test_share.scheme.cached_sync');
      final atKey = (AtKey.shared(keyName, sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(5 * TestConstants.oneMinuteMillis)
            ..cache(1000, true))
          .build();
      await ac1.put(atKey, clearText, putRequestOptions: putOptions);
      await E2ESyncService.getInstance().syncData(ac1.syncService);

      await Future.delayed(Duration(seconds: 5));

      AtClient ac2 = await getAtClient(atSign_2);
      ac2.atChops!.schemes.register(schemeName, TestCryptoScheme());
      await E2ESyncService.getInstance().syncData(ac2.syncService);
      final getResult = await ac2.get(AtKey()
        ..key = keyName
        ..sharedBy = atSign_1);

      expect(getResult.metadata?.appMetadata?.encryptionScheme, schemeName);
      expect(getResult.metadata?.isCached, true);
      expect(getResult.value, 'twin');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('expected failure: shouldEncrypt false does not invoke custom scheme',
        () async {
      final schemeName = uniqueSchemeName('testscheme');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..shouldEncrypt = false
        ..encryptionScheme = schemeName;
      AtClient ac1 = await getAtClient(atSign_1);
      ac1.atChops!.schemes.register(schemeName, TestCryptoScheme());
      final keyName = uniqueKeyName('test_share.scheme.plaintext');
      await ac1.put(sharedKey(keyName), clearText,
          putRequestOptions: putOptions);

      AtClient ac2 = await getAtClient(atSign_2);
      ac2.atChops!.schemes.register(schemeName, TestCryptoScheme());
      final getResult =
          await ac2.get(sharedKey(keyName), getRequestOptions: getOptions);

      expect(getResult.metadata?.isEncrypted, false);
      expect(getResult.value, clearText);
    });

    test('expected failure: notification delivery preserves custom scheme',
        () async {
      final schemeName = uniqueSchemeName('testscheme');
      AtClient ac2 = await getAtClient(atSign_2);
      ac2.atChops!.schemes.register(schemeName, TestCryptoScheme());
      final keyName = uniqueKeyName('test_share.scheme.notify');
      final notificationFuture = ac2.notificationService
          .subscribe(regex: keyName, shouldDecrypt: true)
          .firstWhere((notification) => notification.key.contains(keyName))
          .timeout(Duration(seconds: 30));

      AtClient ac1 = await getAtClient(atSign_1);
      ac1.atChops!.schemes.register(schemeName, TestCryptoScheme());
      final atKey = sharedKey(keyName);
      atKey.metadata.appMetadata = AppMetadata(schemeName);
      final notificationResult = await ac1.notificationService
          .notify(NotificationParams.forUpdate(atKey, value: clearText));

      expect(notificationResult.notificationStatusEnum,
          NotificationStatusEnum.delivered);

      final notification = await notificationFuture;
      expect(notification.value, 'twin');
    }, timeout: Timeout(Duration(minutes: 1)));
  });
}
