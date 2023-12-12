import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:at_utils/at_logger.dart';

late AtClient sharedByAtClient;
late AtClient sharedWithAtClient;
late String sharedByAtSign;
late String sharedWithAtSign;
final namespace = 'wavi';

void main() {
  setUpAll(() async {
    sharedByAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedByAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
    // Initialize sharedWithAtSign
    sharedWithAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedWithAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    // Setting sharedByAtSign atClient instance to context.
    sharedByAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
  });

  test(
      'A test to verify cached key is deleted in sharedWith secondary when CCD is set to true',
      () async {
    AtSignLogger.root_level = 'finer';
    // Create a key with TTR set
    var key = 'deletecachedkey-${Uuid().v4().hashCode}';
    var atKey =
        (AtKey.shared(key, namespace: namespace, sharedBy: sharedByAtSign)
              ..sharedWith(sharedWithAtSign)
              ..cache(-1, true))
            .build();
    sharedByAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    var putResult = await sharedByAtClient.put(atKey, 'dummy_cached_value');
    assert(putResult == true);
    await E2ESyncService.getInstance().syncData(sharedByAtClient.syncService,
        syncOptions: SyncOptions()..key = atKey.toString());

    // Switch to sharedWith AtSign and fetch the cached key
    sharedWithAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedWithAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    var cachedAtKey = AtKey()
      ..key = key
      ..sharedWith = sharedWithAtSign
      ..sharedBy = sharedByAtSign
      ..namespace = namespace
      ..metadata = (Metadata()..isCached = true);
    await E2ESyncService.getInstance().syncData(sharedWithAtClient.syncService,
        syncOptions: SyncOptions()..key = cachedAtKey.toString());
    var getResponse = await sharedWithAtClient.get(cachedAtKey);
    expect(getResponse.value, 'dummy_cached_value');

    // Switch back to sharedBy AtSign and delete the key
    sharedByAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    await sharedByAtClient.delete(atKey);
    await E2ESyncService.getInstance().syncData(sharedByAtClient.syncService,
        syncOptions: SyncOptions()..key = atKey.toString());

    // Switch to sharedWith AtSign and let the deleted cached key sync to local Secondary
    sharedWithAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedWithAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    await E2ESyncService.getInstance().syncData(sharedWithAtClient.syncService,
        syncOptions: SyncOptions()..key = cachedAtKey.toString());
    expect(
        sharedWithAtClient
            .getLocalSecondary()
            ?.keyStore
            ?.isKeyExists(cachedAtKey.toString()),
        false);
    // When sync runs the test remains idle and timeout after 30 seconds
    // Adding timeout to allow sync to complete on current atSign and sharedWith atSign.
  }, timeout: Timeout(Duration(minutes: 1)));

  test(
      'A test to verify cached key is deleted when receiver deletes the cached key in the local',
      () async {
    var key = 'testcachedkey-${Uuid().v4().hashCode}';
    var atKey =
        (AtKey.shared(key, namespace: namespace, sharedBy: sharedByAtSign)
              ..sharedWith(sharedWithAtSign)
              ..cache(-1, true))
            .build();
    var value = 'test_cached_value';

    var currentAtClient = (await AtClientManager.getInstance().setCurrentAtSign(
            sharedByAtSign,
            namespace,
            TestPreferences.getInstance().getPreference(sharedByAtSign)))
        .atClient;
    // notifying a key with ttr to shared with atSign
    await currentAtClient.put(atKey, value);
    await E2ESyncService.getInstance().syncData(sharedByAtClient.syncService,
        syncOptions: SyncOptions()..key = atKey.toString());

    var sharedWithAtClient = (await AtClientManager.getInstance()
            .setCurrentAtSign(sharedWithAtSign, namespace,
                TestPreferences.getInstance().getPreference(sharedWithAtSign)))
        .atClient;
    var cachedAtKey = AtKey()
      ..key = key
      ..sharedWith = sharedWithAtSign
      ..sharedBy = sharedByAtSign
      ..namespace = namespace
      ..metadata = (Metadata()..isCached = true);
    await E2ESyncService.getInstance().syncData(sharedWithAtClient.syncService,
        syncOptions: SyncOptions()..key = cachedAtKey.toString());

    // Assert cached key is present in the local storage of the sharedWith atSign
    var getResponse = await sharedWithAtClient.get(cachedAtKey);
    expect(getResponse.value, 'test_cached_value');

    var scanResultBeforeDelete = await sharedWithAtClient
        .getRemoteSecondary()!
        .executeCommand('scan $key\n', auth: true);
    expect(scanResultBeforeDelete!.contains(cachedAtKey.toString()), true);
    // Delete the cached key in the local secondary of sharedWith atSign
    var deleteResult = await sharedWithAtClient.delete(cachedAtKey);
    expect(deleteResult, true);

    // Sync the deleted cached key commit entry to secondary of sharedWith atSign
    await E2ESyncService.getInstance().syncData(sharedWithAtClient.syncService,
        syncOptions: SyncOptions()..key = cachedAtKey.toString());
    // Asserts cached key is deleted from the local storage in the sharedWith atSign
    expect(
        sharedWithAtClient
            .getLocalSecondary()
            ?.keyStore
            ?.isKeyExists(cachedAtKey.toString()),
        false);
    // Asserts cached key is deleted from the server in the sharedWith atSign
    var scanResultAfterDelete = await sharedWithAtClient
        .getRemoteSecondary()!
        .executeCommand('scan $key\n', auth: true);
    expect(scanResultAfterDelete!.contains(cachedAtKey.toString()), false);
  }, timeout: Timeout(Duration(minutes: 1)));
}
