import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';


void main() async {
  late String sharedByAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';
  var uuid = Uuid();

  setUpAll(() async {
    sharedByAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['fourthAtSign'];
    String authType = ConfigUtil.getYaml()['authType'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedByAtSign, namespace, authType: authType);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace, authType: authType);
  });

  Future<void> setAtSignOneAutoNotify(bool autoNotify) async {
    //  reset the autoNotify to true
    await AtClientManager.getInstance().setCurrentAtSign(sharedByAtSign,
        namespace, TestPreferences.getInstance().getPreference(sharedByAtSign));

    var configResult = await AtClientManager.getInstance()
        .atClient
        .getRemoteSecondary()!
        .executeCommand('config:set:autoNotify=$autoNotify\n', auth: true);
    if (configResult == null) {
      fail('failed to set auto config to $autoNotify');
    }
    expect(configResult.contains('data:ok'), true);
  }

  /// The purpose of this test is to verify the following:
  /// 1. Share a key from sharedByAtSign to sharedWithAtSign with ttr, with autoNotify:true
  /// 2. Perform lookup from sharedWithAtSign  and assert on value - initial value should be returned.
  /// 3. Set the autoNotify to false using the config verb
  /// 4. Update the existing key to a new value
  /// 4. lookup with bypass_cache set to true should return the updated value
  /// 5. lookup with bypass_cache set to false should return the old value
  test('A test to verify bypassCache', () async {
    int uniqueId = uuid.v4().hashCode;
    String keyEntity = 'test_bypass_cached_key-$uniqueId';
    String initialValue = 'initial_value-$uniqueId';
    String updatedValue = 'updated_value-$uniqueId';

    AtKey testByPassCacheAtKey = AtKey()
      ..key = keyEntity
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ttl = 900000);

    // Ensure autoNotify is set to true to begin with
    await setAtSignOneAutoNotify(true);

    // Set sharedBy atSign as currentAtSign and Put the initial value
    await AtClientManager.getInstance().setCurrentAtSign(sharedByAtSign,
        namespace, TestPreferences.getInstance().getPreference(sharedByAtSign));

    var putResult = await AtClientManager.getInstance()
        .atClient
        .put(testByPassCacheAtKey, initialValue);
    expect(putResult, true);
    // Sync the data to the remote secondary
    await E2ESyncService.getInstance().syncData(
        AtClientManager.getInstance().atClient.syncService,
        syncOptions: SyncOptions()..key = testByPassCacheAtKey.toString());

    // Give it a couple of seconds to propagate from one atServer to the other
    await Future.delayed(Duration(seconds: 2));

    // Switch to sharedWithAtSign
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(sharedWithAtSign));

    var cachedTestByPassCacheAtKey = AtKey()
      ..key = keyEntity
      ..sharedWith = sharedWithAtSign
      ..namespace = namespace
      ..sharedBy = sharedByAtSign
      ..metadata = (Metadata()..isCached = true);
    await E2ESyncService.getInstance().syncData(
        AtClientManager.getInstance().atClient.syncService,
        syncOptions: SyncOptions()
          ..key = cachedTestByPassCacheAtKey.toString());

    var getKey = AtKey()
      ..key = keyEntity
      ..sharedBy = sharedByAtSign;
    var getResult = await AtClientManager.getInstance().atClient.get(getKey);
    expect(getResult.value, initialValue);
    // Since the put request has a ttr in metadata, a cached key will be created.
    // When a cached key is available, value will be fetched from a cached key.
    // Hence isCached should be true.
    expect(getResult.metadata!.isCached, true);

    // Switch back to sharedByAtSign to update the value of the key.
    await AtClientManager.getInstance().setCurrentAtSign(sharedByAtSign,
        namespace, TestPreferences.getInstance().getPreference(sharedByAtSign));

    try {
      // Set autoNotify to false so that the update doesn't propagate to sharedWith AtSign automatically
      await setAtSignOneAutoNotify(false);

      var newPutResult = await AtClientManager.getInstance()
          .atClient
          .put(testByPassCacheAtKey, updatedValue);
      expect(newPutResult, true);
      // Sync the data to the remote secondary
      await E2ESyncService.getInstance().syncData(
          AtClientManager.getInstance().atClient.syncService,
          syncOptions: SyncOptions()..key = testByPassCacheAtKey.toString());

      // As atSignTwo
      await AtClientManager.getInstance().setCurrentAtSign(
          sharedWithAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(sharedWithAtSign));

      // Sync - after this we still should have the old value
      await E2ESyncService.getInstance()
          .syncData(AtClientManager.getInstance().atClient.syncService);

      // Get result with bypassCache set to false
      // Since bypassCache is set to false, the value from the returned from the
      // cached key. So the initial value should be returned.
      getKey = AtKey()
        ..key = keyEntity
        ..sharedBy = sharedByAtSign;
      getResult = await AtClientManager.getInstance().atClient.get(getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = false);
      expect(getResult.value, initialValue);
      expect(getResult.metadata!.isCached, true);

      // Get result with bypassCache set to true
      // Since bypassCache is set to true, a lookup should be performed to the
      // sharedBy AtSign and updated value should be fetched.
      getKey = AtKey()
        ..key = keyEntity
        ..sharedBy = sharedByAtSign;
      getResult = await AtClientManager.getInstance().atClient.get(getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = true);
      expect(getResult.value, updatedValue);
      expect(getResult.metadata!.isCached, false);
      // Sync - after this we should now have the new value
      await E2ESyncService.getInstance().syncData(
          AtClientManager.getInstance().atClient.syncService,
          syncOptions: SyncOptions()
            ..key = cachedTestByPassCacheAtKey.toString());

      // Get Result with byPassCache set to false again
      // should also now return the new value, since cached value will have been updated with the
      // results of the remote lookup, and the cached value will have been synced to the client
      getKey = AtKey()
        ..key = keyEntity
        ..sharedBy = sharedByAtSign;
      var getResultWithFalse = await AtClientManager.getInstance().atClient.get(
          getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = false);
      expect(getResultWithFalse.value, updatedValue);
      expect(getResultWithFalse.metadata!.isCached, true);
    } finally {
      await setAtSignOneAutoNotify(true);
    }
  });
}
