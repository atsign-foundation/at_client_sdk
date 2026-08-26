import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_end2end_test/utils/test_crypto_provider.dart';
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
        .testInitializer(atSign_1, namespace, authType,
            posture: PqPosture.legacy);
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign_2, namespace, authType,
            posture: PqPosture.legacy);
  });

  tearDownAll(() {});

  Future<AtClient> getAtClient(
    String atSign, {
    String? testProviderId,
  }) async {
    final preference = TestPreferences.getInstance().getPreference(atSign,
        posture: PqPosture.legacy);
    if (testProviderId != null) {
      preference.crypto = CryptoConfig(
        defaultProviderId: legacyCryptoProviderId,
        providers: [
          TestCryptoProvider(testProviderId),
        ],
      );
    }

    // The provider is configured via the preference, not registered by this
    // test: switching to this atSign re-uses the cached AtClient, and
    // AtClientImpl.create() adopts this preference's crypto config onto it
    // (CryptoRuntime resolves against the live preference.crypto). This test
    // depends on that production behaviour.
    final atClientManager =
        await AtClientManager.getInstance().setCurrentAtSign(
      atSign,
      namespace,
      preference,
    );
    return atClientManager.atClient;
  }

  // Like getAtClient, but configures an explicit list of providers (for the
  // multi-provider / config-adoption machinery tests below).
  Future<AtClient> getAtClientWith(
    String atSign,
    List<CryptoProvider> providers, {
    String defaultProviderId = legacyCryptoProviderId,
  }) async {
    final preference = TestPreferences.getInstance().getPreference(atSign,
        posture: PqPosture.legacy)
      ..crypto = CryptoConfig(
        defaultProviderId: defaultProviderId,
        providers: providers,
      );
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, namespace, preference);
    return atClientManager.atClient;
  }

  String uniqueKeyName(String prefix) {
    return '$prefix.${DateTime.now().microsecondsSinceEpoch}';
  }

  String uniqueProviderId(String prefix) {
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
    test('✓ with custom crypto provider', () async {
      final providerId = uniqueProviderId('testprovider');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..cryptoProviderId = providerId;
      //step 1. put with app specified provider
      AtClient ac1 = await getAtClient(atSign_1, testProviderId: providerId);
      var atKey = sharedKey(uniqueKeyName('test_share.provider'));
      await ac1.put(atKey, clearText, putRequestOptions: putOptions);

      //step 2. get with the shared atsign
      AtClient ac2 = await getAtClient(atSign_2, testProviderId: providerId);
      var getResult = await ac2.get(atKey, getRequestOptions: getOptions);
      // see `TestCryptoProvider` for the returning values
      expect(getResult.value, 'twin');
    });
    test('✘ with custom crypto provider: fails due to ac2 not having provider',
        () async {
      final providerId = uniqueProviderId('testprovider');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..cryptoProviderId = providerId;
      //step 1. put with app specified provider
      AtClient ac1 = await getAtClient(atSign_1, testProviderId: providerId);
      var atKey = sharedKey(uniqueKeyName('test_share.provider'));
      await ac1.put(atKey, clearText, putRequestOptions: putOptions);

      //step 2. get with the shared atsign, should throw
      AtClient ac2 = await getAtClient(atSign_2);
      expect(
          () async => await ac2.get(atKey, getRequestOptions: getOptions),
          throwsA(
            isA<CryptoProviderNotRegistered>(),
          ));
    });

    test('custom provider survives a fresh remote get', () async {
      final providerId = uniqueProviderId('testprovider');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..cryptoProviderId = providerId;
      AtClient ac1 = await getAtClient(atSign_1, testProviderId: providerId);
      final keyName = uniqueKeyName('test_share.provider.fresh_remote');
      await ac1.put(sharedKey(keyName), clearText,
          putRequestOptions: putOptions);

      AtClient ac2 = await getAtClient(atSign_2, testProviderId: providerId);
      final freshReadKey = sharedKey(keyName);
      var getResult =
          await ac2.get(freshReadKey, getRequestOptions: getOptions);

      expect(getResult.metadata?.appMetadata?.providerId, providerId);
      expect(getResult.value, 'twin');
    });

    test('custom provider survives cached local sync', () async {
      final providerId = uniqueProviderId('testprovider');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..cryptoProviderId = providerId;
      AtClient ac1 = await getAtClient(atSign_1, testProviderId: providerId);
      final keyName = uniqueKeyName('test_share.provider.cached_sync');
      final atKey = (AtKey.shared(keyName, sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(5 * TestConstants.oneMinuteMillis)
            ..cache(1000, true))
          .build();
      await ac1.put(atKey, clearText, putRequestOptions: putOptions);
      await E2ESyncService.getInstance().syncData(ac1.syncService);

      await Future.delayed(Duration(seconds: 5));

      AtClient ac2 = await getAtClient(atSign_2, testProviderId: providerId);
      await E2ESyncService.getInstance().syncData(ac2.syncService);
      final getResult = await ac2.get(AtKey()
        ..key = keyName
        ..sharedBy = atSign_1);

      expect(getResult.metadata?.appMetadata?.providerId, providerId);
      expect(getResult.metadata?.isCached, true);
      expect(getResult.value, 'twin');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('shouldEncrypt false does not invoke custom provider', () async {
      final providerId = uniqueProviderId('testprovider');
      PutRequestOptions putOptions = PutRequestOptions()
        ..useRemoteAtServer = true
        ..shouldEncrypt = false
        ..cryptoProviderId = providerId;
      AtClient ac1 = await getAtClient(atSign_1, testProviderId: providerId);
      final keyName = uniqueKeyName('test_share.provider.plaintext');
      await ac1.put(sharedKey(keyName), clearText,
          putRequestOptions: putOptions);

      AtClient ac2 = await getAtClient(atSign_2, testProviderId: providerId);
      final getResult =
          await ac2.get(sharedKey(keyName), getRequestOptions: getOptions);

      expect(getResult.metadata?.isEncrypted, false);
      expect(getResult.value, clearText);
    });

    test('notification delivery preserves custom provider', () async {
      final providerId = uniqueProviderId('testprovider');
      final keyName = uniqueKeyName('test_share.provider.notify');

      // Notify first, THEN switch to the receiver and subscribe. A live
      // listener on atSign_2 cannot survive the getAtClient(atSign_1) switch:
      // AtClientManager is a singleton and setCurrentAtSign stops the previous
      // current AtClient, tearing down its monitor. Subscribing after the
      // notify relies on the receiver's catch-up to replay the stored
      // notification through the provider's decrypt path (decrypt() -> 'twin').
      //
      // Quirk: getLastNotificationTime() returns null on its FIRST call for a
      // given keystore, and a monitor started with null asks the atServer for
      // no replay at all — so the notification above is never seen. Burn that
      // first call here. Without it this test only passes when some other test
      // file happened to start atSign_2's monitor first, which is what made it
      // flake.
      final receiverNotifications =
          (await getAtClient(atSign_2, testProviderId: providerId))
              .notificationService as NotificationServiceImpl;
      await receiverNotifications.getLastNotificationTime();
      expect(await receiverNotifications.getLastNotificationTime(), isNotNull,
          reason: 'without this the monitor below asks for no replay');

      AtClient ac1 = await getAtClient(atSign_1, testProviderId: providerId);
      final atKey = sharedKey(keyName);
      atKey.metadata.appMetadata = AppMetadata(providerId: providerId);
      final notificationResult = await ac1.notificationService
          .notify(NotificationParams.forUpdate(atKey, value: clearText));

      expect(notificationResult.notificationStatusEnum,
          NotificationStatusEnum.delivered);

      AtClient ac2 = await getAtClient(atSign_2, testProviderId: providerId);
      final notification = await ac2.notificationService
          .subscribe(regex: keyName, shouldDecrypt: true)
          .firstWhere((notification) => notification.key.contains(keyName))
          .timeout(Duration(seconds: 30));
      expect(notification.value, 'twin');
    }, timeout: Timeout(Duration(minutes: 1)));
  });

  group('Pluggable encryption / decryption — provider machinery', () {
    final getOptions = GetRequestOptions()
      ..bypassCache = true
      ..useRemoteAtServer = true;
    PutRequestOptions putWith(String providerId) => PutRequestOptions()
      ..useRemoteAtServer = true
      ..cryptoProviderId = providerId;

    test('SDK stamps providerId + isEncrypted when the provider does not',
        () async {
      final providerId = uniqueProviderId('bareprov');
      final keyName = uniqueKeyName('test_share.bare');
      // _MarkerProvider with stamp:false deliberately touches no metadata.
      AtClient ac1 = await getAtClientWith(
          atSign_1, [_MarkerProvider(providerId, plaintext: 'bare-plain')]);
      final atKey = sharedKey(keyName);
      await ac1.put(atKey, clearText, putRequestOptions: putWith(providerId));

      // The runtime stamped routing metadata on the provider's behalf.
      expect(atKey.metadata.appMetadata?.providerId, providerId);
      expect(atKey.metadata.isEncrypted, true);

      // The receiver decrypts — only possible because isEncrypted was stamped
      // (otherwise the value would come back undecrypted).
      AtClient ac2 = await getAtClientWith(
          atSign_2, [_MarkerProvider(providerId, plaintext: 'bare-plain')]);
      final getResult =
          await ac2.get(sharedKey(keyName), getRequestOptions: getOptions);
      expect(getResult.metadata?.appMetadata?.providerId, providerId);
      expect(getResult.value, 'bare-plain');
    });

    test(
        're-setting an atSign adopts the new crypto config (replacing the old)',
        () async {
      final idA = uniqueProviderId('padoptA');
      final idB = uniqueProviderId('padoptB');

      // Configure atSign_1 with provider A, then RE-SET it with provider B.
      await getAtClientWith(atSign_1, [_MarkerProvider(idA)]);
      AtClient ac = await getAtClientWith(atSign_1, [_MarkerProvider(idB)]);

      // A put routed to B works — the new config was adopted onto the re-used
      // client.
      final keyB = sharedKey(uniqueKeyName('test_share.adoptB'));
      await ac.put(keyB, clearText, putRequestOptions: putWith(idB));
      expect(keyB.metadata.appMetadata?.providerId, idB);

      // ...but a put routed to A now fails: adoption replaced the config, so A
      // is gone (and A is not the built-in legacy fallback).
      final keyA = sharedKey(uniqueKeyName('test_share.adoptA'));
      expect(
        () async =>
            await ac.put(keyA, clearText, putRequestOptions: putWith(idA)),
        throwsA(isA<CryptoProviderNotRegistered>()),
      );
    });

    test('routes by providerId among multiple configured providers', () async {
      final idA = uniqueProviderId('prouteA');
      final idB = uniqueProviderId('prouteB');
      List<CryptoProvider> providers() => [
            _MarkerProvider(idA, plaintext: 'alpha'),
            _MarkerProvider(idB, plaintext: 'beta'),
          ];
      final keyNameA = uniqueKeyName('test_share.routeA');
      final keyNameB = uniqueKeyName('test_share.routeB');

      AtClient ac1 = await getAtClientWith(atSign_1, providers());
      final keyA = sharedKey(keyNameA);
      final keyB = sharedKey(keyNameB);
      await ac1.put(keyA, clearText, putRequestOptions: putWith(idA));
      await ac1.put(keyB, clearText, putRequestOptions: putWith(idB));
      expect(keyA.metadata.appMetadata?.providerId, idA);
      expect(keyB.metadata.appMetadata?.providerId, idB);

      AtClient ac2 = await getAtClientWith(atSign_2, providers());
      expect(
          (await ac2.get(sharedKey(keyNameA), getRequestOptions: getOptions))
              .value,
          'alpha');
      expect(
          (await ac2.get(sharedKey(keyNameB), getRequestOptions: getOptions))
              .value,
          'beta');
    });
  });
}

/// Test provider whose decrypt yields a fixed [plaintext]. It deliberately
/// touches no metadata on encrypt, so the SDK's own stamping is observable.
class _MarkerProvider extends CryptoProvider {
  @override
  final String id;
  final String plaintext;

  _MarkerProvider(this.id, {this.plaintext = 'decrypted'});

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      'cipher';

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      plaintext;
}
