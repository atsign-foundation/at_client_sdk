import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';

import 'package:test/test.dart';

void main() async {
  late AtClientManager currentAtClientManager;
  late AtClientManager sharedWithAtClientManager;
  late String currentAtSign;
  late String sharedWithAtSign;
  final namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(currentAtSign, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(sharedWithAtSign, namespace);
  });

  /// The purpose of this test is to verify the following:
  /// 1. Share a key from atsign_1 to atsign_2 with ttr, with autoNotify:true
  /// 2. lookup from atsign_2 returns the correct value
  /// 3.  Set the autoNotify to false using the config verb
  /// 4. Update the existing key to a new value
  /// 4. lookup with bypass_cache set to true should return the updated value
  /// 5. lookup with bypass_cache set to false should return the old value
  test('bypass cache test', () async {
    var verificationKey = AtKey()
      ..key = 'verificationnumber'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata()..ttr = 1000);
    var oldValue = '0873';
    // updating the key to the currentAtSign
    currentAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(currentAtSign, namespace,
            TestPreferences.getInstance().getPreference(currentAtSign));
    var putResult =
        await currentAtClientManager.atClient.put(verificationKey, oldValue);
    expect(putResult, true);
    // Sync the data to the remote secondary
    await E2ESyncService.getInstance()
        .syncData(currentAtClientManager.syncService);

    // Setting sharedWithAtSign atClient instance to context.
    sharedWithAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestPreferences.getInstance().getPreference(sharedWithAtSign));
    await E2ESyncService.getInstance()
        .syncData(sharedWithAtClientManager.syncService);
    var getKey = AtKey()
      ..key = 'verificationnumber'
      ..sharedBy = currentAtSign;
    var getResult = await sharedWithAtClientManager.atClient.get(getKey);
    expect(getResult.value, oldValue);
    print('get Result is $getResult');

    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(currentAtSign,
        namespace, TestPreferences.getInstance().getPreference(currentAtSign));
    try {
      // set auto notify to false
      var configResult = await currentAtClientManager.atClient
          .getRemoteSecondary()!
          .executeCommand('config:set:autoNotify=false\n', auth: true);
      expect(configResult, contains('data:ok'));
      // adding a delay for 2 seconds till the config value gets updated
      await Future.delayed(Duration(seconds: 3));
      // Updating the same key with a new value
      var verificationKeyNew = AtKey()
        ..key = 'verificationnumber'
        ..sharedWith = sharedWithAtSign;
      var newValue = '9900';
      var newPutResult = await currentAtClientManager.atClient
          .put(verificationKeyNew, newValue);
      expect(newPutResult, true);
      await E2ESyncService.getInstance()
          .syncData(currentAtClientManager.syncService);

      // Setting sharedWithAtSign atClient instance to context.
      sharedWithAtClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(sharedWithAtSign, namespace,
              TestPreferences.getInstance().getPreference(sharedWithAtSign));
      await E2ESyncService.getInstance()
          .syncData(sharedWithAtClientManager.syncService);
      //  get result with bypassCache set to true
      // should return the newly updated value
      getResult = await sharedWithAtClientManager.atClient.get(getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = true);
      print('get result with bypass cache true $getResult');
      expect(getResult.value, newValue);
      // get Result with byPassCache set to false
      // should return the old value
      // adding a delay
      await Future.delayed(Duration(seconds: 3));
      var getResultWithFalse = await sharedWithAtClientManager.atClient.get(
          getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = false);
      print('get result with bypass cache false $getResultWithFalse');
      expect(getResultWithFalse.value, oldValue);
      //  reset the autoNotify to false
      await AtClientManager.getInstance().setCurrentAtSign(
          currentAtSign,
          namespace,
          TestPreferences.getInstance().getPreference(currentAtSign));
    } finally {
      // Moving the config:set:autoNotify=true to finally block because if
      // test fails in between the autoNotify on the atSign remains false.
      var configResult = await currentAtClientManager.atClient
          .getRemoteSecondary()!
          .executeCommand('config:set:autoNotify=true\n', auth: true);
      if (configResult == null) {
        assert(fail('failed to set auto config to true'));
      }
      assert(configResult!.contains('data:ok'), true);
    }
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 5)));
}
