import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:at_utils/at_logger.dart';

late AtClient sharedByAtClient;
late AtClient sharedWithAtClient;
late String sharedByAtSign;
late String sharedWithAtSign;
final namespace = 'wavi';

void main() {
  AtSignLogger.root_level = 'finer';
  setUpAll(() async {
    sharedByAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedByAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
    // Initialize sharedWithAtSign
    sharedWithAtClient = (await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign))).atClient;
    // Setting sharedByAtSign atClient instance to context.
    sharedByAtClient = (await AtClientManager.getInstance()
        .setCurrentAtSign(sharedByAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign))).atClient;
  });

  test(
      'A test to verify deletion of key when overriding the namespace in atKey',
      () async {
    // The namespace in the preference is "wavi". Overriding the namespace in the atKey to "buzz"
    var atKey = (AtKey.shared('keyNamespaceOverriding',
            namespace: 'buzz', sharedBy: sharedByAtSign)
          ..sharedWith(sharedWithAtSign))
        .build();
    await sharedByAtClient.put(atKey, 'dummy_value');
    expect(
        sharedByAtClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        true);

    // Delete the key
    await sharedByAtClient.delete(atKey);
    expect(
        sharedByAtClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        false);
  });

  test(
      'A test to verify cached key is deleted in sharedWith secondary when CCD is set to true',
      () async {
    var atKey = (AtKey.shared('deletecachedkey', sharedBy: sharedByAtSign)
          ..sharedWith(sharedWithAtSign)
          ..cache(-1, true))
        .build();
    sharedByAtClient = (await AtClientManager.getInstance()
        .setCurrentAtSign(sharedByAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign))).atClient;
    await sharedByAtClient.put(atKey, 'dummy_cached_value');
    await E2ESyncService.getInstance()
        .syncData(sharedByAtClient.syncService);

    sharedWithAtClient = (await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign))).atClient;
    await E2ESyncService.getInstance()
        .syncData(sharedWithAtClient.syncService);

    var cachedAtKey = AtKey()
      ..key = 'deletecachedkey'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()..isCached = true);
    var getResponse = await sharedWithAtClient.get(cachedAtKey);
    expect(getResponse.value, 'dummy_cached_value');
    // Delete the key
    sharedByAtClient =( await AtClientManager.getInstance()
        .setCurrentAtSign(sharedByAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign))).atClient;
    await sharedByAtClient.delete(atKey);
    await E2ESyncService.getInstance()
        .syncData(sharedByAtClient.syncService);

    // Sync the deleted cached key commit entry to local secondary of sharedWith atSign
    sharedWithAtClient = (await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign))).atClient;
    await E2ESyncService.getInstance()
        .syncData(sharedWithAtClient.syncService);

    // Asserts cached key is deleted from the local storage in the sharedWith atSign
    expect(
        sharedWithAtClient
            .getLocalSecondary()
            ?.keyStore
            ?.isKeyExists(
                'cached:$sharedWithAtSign:deletecachedkey$sharedByAtSign}'),
        false);
    // When sync runs the test remains idle and timeout after 30 seconds
    // Adding timeout to allow sync to complete on current atSign and sharedWith atSign.
  }, timeout: Timeout(Duration(minutes: 1)));

  test(
      'A test to verify cached key is deleted when receiver deletes the cached key in the local',
      () async {
    var key = 'testcachedkey';
    var atKey = (AtKey.shared(key, sharedBy: sharedByAtSign)
          ..sharedWith(sharedWithAtSign)
          ..cache(-1, true))
        .build();
    var value = 'test_cached_value';
    var currentAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    // notifying a key with ttr to shared with atsign
    await currentAtClient.put(atKey, '$value');
    await E2ESyncService.getInstance()
        .syncData(sharedByAtClient.syncService);
    var sharedWithAtClient = (await AtClientManager.getInstance()
            .setCurrentAtSign(sharedWithAtSign, namespace,
                TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    await E2ESyncService.getInstance()
        .syncData(sharedWithAtClient.syncService);

    var cachedAtKey = AtKey()
      ..key = key
      ..sharedWith = sharedWithAtSign
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()..isCached = true);
    // Assert cached key is present in the local storage of the sharedWith atSign
    var getResponse = await sharedWithAtClient.get(cachedAtKey);
    expect(getResponse.value, 'test_cached_value');

    // creating another atkey instance to delete the cached key
    // due to the following bug - https://github.com/atsign-foundation/at_client_sdk/issues/939
    cachedAtKey = AtKey()
      ..key = key
      ..sharedWith = sharedWithAtSign
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()..isCached = true);
    // cached key to be fetched from secondary
    var serverCachedKey =
        'cached:$sharedWithAtSign:$key.$namespace$sharedByAtSign';
    var scanResultBeforeDelete = await sharedWithAtClient
        .getRemoteSecondary()!
        .executeCommand('scan\n', auth: true);
    expect(
        scanResultBeforeDelete!.contains(
            serverCachedKey),
        true);
    // Delete the cached key in the local secondary of sharedWith atSign
    var deleteResult = await sharedWithAtClient.delete(cachedAtKey);
    expect(deleteResult, true);

    // Sync the deleted cached key commit entry to secondary of sharedWith atSign
    await E2ESyncService.getInstance().syncData(sharedWithAtClient.syncService);
    // Asserts cached key is deleted from the local storage in the sharedWith atSign
    expect(
        sharedWithAtClient.getLocalSecondary()?.keyStore?.isKeyExists(
            serverCachedKey),
        false);
    // Asserts cached key is deleted from the server in the sharedWith atSign
    var scanResultAfterDelete = await sharedWithAtClient
        .getRemoteSecondary()!
        .executeCommand('scan\n', auth: true);
    expect(
        scanResultAfterDelete!.contains(
            serverCachedKey),
        false);
  }, timeout: Timeout(Duration(minutes: 1)));
}
