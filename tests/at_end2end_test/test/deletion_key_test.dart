import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';

late AtClientManager currentAtClientManager;
late AtClientManager sharedWithAtClientManager;
late String currentAtSign;
late String sharedWithAtSign;
final namespace = 'wavi';

void main() {
  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
    // Initialize sharedWithAtSign
    sharedWithAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign));
    // Setting currentAtSign atClient instance to context.
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
  });

  test(
      'A test to verify deletion of key when overriding the namespace in atKey',
      () async {
    // The namespace in the preference is "wavi". Overriding the namespace in the atKey to "buzz"
    var atKey = (AtKey.shared('keyNamespaceOverriding',
            namespace: 'buzz', sharedBy: currentAtSign)
          ..sharedWith(sharedWithAtSign))
        .build();
    await currentAtClientManager.atClient.put(atKey, 'dummy_value');
    expect(
        currentAtClientManager.atClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        true);

    // Delete the key
    await currentAtClientManager.atClient.delete(atKey);
    expect(
        currentAtClientManager.atClient
            .getLocalSecondary()!
            .keyStore!
            .isKeyExists(atKey.toString()),
        false);
  });

  test(
      'A test to verify cached key is deleted in sharedWith secondary when CCD is set to true',
      () async {
    var atKey = (AtKey.shared('deletecachedkey', sharedBy: currentAtSign)
          ..sharedWith(sharedWithAtSign)
          ..cache(-1, true))
        .build();
    await currentAtClientManager.atClient.put(atKey, 'dummy_cached_value');
    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    sharedWithAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign));
    await E2ESyncService.getInstance()
        .syncData(sharedWithAtClientManager.atClient.syncService);

    var cachedAtKey = AtKey()
      ..key = 'deletecachedkey'
      ..sharedWith = sharedWithAtSign
      ..sharedBy = currentAtSign
      ..metadata = (Metadata()..isCached = true);
    var getResponse = await sharedWithAtClientManager.atClient.get(cachedAtKey);
    expect(getResponse.value, 'dummy_cached_value');
    // Delete the key
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
    await currentAtClientManager.atClient.delete(atKey);
    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.atClient.syncService);

    // Sync the deleted cached key commit entry to local secondary of sharedWith atSign
    sharedWithAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign));
    await E2ESyncService.getInstance()
        .syncData(sharedWithAtClientManager.atClient.syncService);

    // Asserts cached key is deleted from the local storage in the sharedWith atSign
    expect(
        sharedWithAtClientManager.atClient
            .getLocalSecondary()
            ?.keyStore
            ?.isKeyExists(
                'cached:$sharedWithAtSign:deletecachedkey$currentAtSign}'),
        false);
    // When sync runs the test remains idle and timeout after 30 seconds
    // Adding timeout to allow sync to complete on current atSign and sharedWith atSign.
  }, timeout: Timeout(Duration(minutes: 1)));
}
