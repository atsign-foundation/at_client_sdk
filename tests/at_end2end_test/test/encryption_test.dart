import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';
import 'package:version/version.dart';

void main() {
  late String atSign_1;
  late String atSign_2;
  final namespace = TestConstants.namespace;

  var clearText = 'Some clear text';

  var logLevelToRestore = AtSignLogger.root_level;
  setUpAll(() async {
    AtSignLogger.root_level = 'SHOUT';
    atSign_1 = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atSign_2 = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign_1, namespace, authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSign_2, namespace, authType);
  });

  tearDownAll(() {
    AtSignLogger.root_level = logLevelToRestore;
  });

  Future<AtClient> getAtClient(String atSign, Version version) async {
    AtClient atClient = (await AtClientManager.getInstance().setCurrentAtSign(
            atSign,
            namespace,
            TestPreferences.getInstance().getPreference(atSign_1)))
        .atClient;

    atClient.getPreferences()!.atProtocolEmitted = version;

    return atClient;
  }

  int ttl = 60000;

  group(
      'Test encryption for sharing, storing shared encryption key in metadata',
      () {
    test('Test put shared, then get, no IV, 1.5 to 1.5', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(1, 5, 0));

      var atKey = (AtKey.shared('test_share.1_5.to.1_5', sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText);
      expect(atKey.metadata.ivNonce, isNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(1, 5, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey);
      expect(getResult.value, clearText);
    }, timeout: Timeout(Duration(minutes: 5)));

    test('Test put shared, then get, no IV, 1.5 to 2.0', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(1, 5, 0));

      var atKey = (AtKey.shared('test_share.1_5.to.2_0', sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText);
      expect(atKey.metadata.ivNonce, isNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(2, 0, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey);
      expect(getResult.value, clearText);
    });

    test('Test put shared, then get, with IV, 2.0 to 2.0', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(2, 0, 0));

      var atKey = (AtKey.shared('test_share.2_0.to.2_0', sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText);
      expect(atKey.metadata.ivNonce, isNotNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(2, 0, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey);
      expect(getResult.value, clearText);
    });

    test('Test put shared, then get, with IV, 2.0 to 1.5', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(2, 0, 0));

      var atKey = (AtKey.shared('test_share.2_0.to.1_5', sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText);
      expect(atKey.metadata.ivNonce, isNotNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(1, 5, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey);
      expect(getResult.value, clearText);
    });
  });

  group(
      'Test encryption for sharing, NOT storing shared encryption key in metadata',
      () {
    PutRequestOptions options = PutRequestOptions()
      ..storeSharedKeyEncryptedMetadata = false;

    test('Test put shared, then get, no IV, 1.5 to 1.5', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(1, 5, 0));

      var atKey = (AtKey.shared('test_share.1_5.to.1_5.no_inlined_key',
              sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: options);
      expect(atKey.metadata.ivNonce, isNull);
      expect(atKey.metadata.sharedKeyEnc, isNull);
      expect(atKey.metadata.pubKeyCS, isNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(1, 5, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey,
          getRequestOptions: GetRequestOptions()..bypassCache = true);
      expect(getResult.value, clearText);
    }, timeout: Timeout(Duration(minutes: 5)));

    test('Test put shared, then get, no IV, 1.5 to 2.0', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(1, 5, 0));

      var atKey = (AtKey.shared('test_share.1_5.to.2_0.no_inlined_key',
              sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: options);
      expect(atKey.metadata.ivNonce, isNull);
      expect(atKey.metadata.sharedKeyEnc, isNull);
      expect(atKey.metadata.pubKeyCS, isNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(2, 0, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey);
      expect(getResult.value, clearText);
    });

    test('Test put shared, then get, with IV, 2.0 to 2.0', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(2, 0, 0));

      var atKey = (AtKey.shared('test_share.2_0.to.2_0.no_inlined_key',
              sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: options);
      expect(atKey.metadata.ivNonce, isNotNull);
      expect(atKey.metadata.sharedKeyEnc, isNull);
      expect(atKey.metadata.pubKeyCS, isNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(2, 0, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey);
      expect(getResult.value, clearText);
    });

    test('Test put shared, then get, with IV, 2.0 to 1.5', () async {
      AtClient atClient_1 = await getAtClient(atSign_1, Version(2, 0, 0));

      var atKey = (AtKey.shared('test_share.2_0.to.1_5.no_inlined_key',
              sharedBy: atSign_1)
            ..sharedWith(atSign_2)
            ..timeToLive(ttl))
          .build();
      await atClient_1.put(atKey, clearText, putRequestOptions: options);
      expect(atKey.metadata.ivNonce, isNotNull);
      expect(atKey.metadata.sharedKeyEnc, isNull);
      expect(atKey.metadata.pubKeyCS, isNull);

      await E2ESyncService.getInstance().syncData(atClient_1.syncService);

      AtClient atClient_2 = await getAtClient(atSign_2, Version(1, 5, 0));
      await E2ESyncService.getInstance().syncData(atClient_2.syncService);

      var getResult = await atClient_2.get(atKey);
      expect(getResult.value, clearText);
    });
  });
}
