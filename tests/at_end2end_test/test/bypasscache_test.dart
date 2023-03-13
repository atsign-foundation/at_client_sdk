import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';

import 'package:test/test.dart';
import 'package:version/version.dart';

void main() async {
  late AtClient clientOne;
  late AtClient clientTwo;
  late String atSignOne;
  late String atSignTwo;
  final namespace = 'wavi';

  setUpAll(() async {
    atSignOne = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atSignTwo = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    await TestSuiteInitializer.getInstance()
        .testInitializer(atSignOne, namespace);
    await TestSuiteInitializer.getInstance()
        .testInitializer(atSignTwo, namespace);
  });

  Future<Version> getVersion(AtClient atClient) async {
    var infoResult = await atClient.getRemoteSecondary()!.executeCommand('info\n');

    expect(infoResult, startsWith('data:{'));
    infoResult = infoResult!.replaceAll('data:', '');
    // Since secondary version has gha<number> appended, remove the gha number from version
    // Hence using split.
    return Version.parse(jsonDecode(infoResult)['version'].split('+')[0]);
  }

  Future<void> setAtSignOneAutoNotify(bool autoNotify) async {
    //  reset the autoNotify to true
    clientOne = (await AtClientManager.getInstance().setCurrentAtSign(
        atSignOne,
        namespace,
        TestPreferences.getInstance().getPreference(atSignOne))).atClient;

    var configResult = await clientOne
        .getRemoteSecondary()!
        .executeCommand('config:set:autoNotify=$autoNotify\n', auth: true);
    if (configResult == null) {
      fail('failed to set auto config to $autoNotify');
    }
    expect(configResult.contains('data:ok'), true);
  }

  /// The purpose of this test is to verify the following:
  /// 1. Share a key from atsign_1 to atsign_2 with ttr, with autoNotify:true
  /// 2. lookup from atsign_2 returns the correct value
  /// 3.  Set the autoNotify to false using the config verb
  /// 4. Update the existing key to a new value
  /// 4. lookup with bypass_cache set to true should return the updated value
  /// 5. lookup with bypass_cache set to false should return the old value
  test('bypass cache test', () async {
    var verificationKey = AtKey()
      ..key = 'verificationNumber'
      ..sharedWith = atSignTwo
      ..metadata = (Metadata()..ttr = 1000);
    var initialValue = '0873';

    // Ensure autoNotify is set to true to begin with
    await setAtSignOneAutoNotify(true);

    // As atSignOne: Put the initial value
    clientOne = (await AtClientManager.getInstance()
        .setCurrentAtSign(atSignOne, namespace,
            TestPreferences.getInstance().getPreference(atSignOne))).atClient;
    var putResult =
        await clientOne.put(verificationKey, initialValue);
    expect(putResult, true);
    // Sync the data to the remote secondary
    await E2ESyncService.getInstance()
        .syncData(clientOne.syncService);

    // Give it a couple of seconds to propagate from one atServer to the other
    await Future.delayed(Duration(seconds: 2));

    // As atSignTwo: do a sync, and do the get, to verify we have the initial value
    clientTwo = (await AtClientManager.getInstance()
        .setCurrentAtSign(atSignTwo, namespace,
            TestPreferences.getInstance().getPreference(atSignTwo))).atClient;
    await E2ESyncService.getInstance()
        .syncData(clientTwo.syncService);
    var getKey = AtKey()
      ..key = 'verificationNumber'
      ..sharedBy = atSignOne;
    var getResult = await clientTwo.get(getKey);
    expect(getResult.value, initialValue);
    print('get Result is $getResult');

    // As atSignOne
    clientOne = (await AtClientManager.getInstance().setCurrentAtSign(atSignOne,
        namespace, TestPreferences.getInstance().getPreference(atSignOne))).atClient;
    try {
      // Set autoNotify to false so that the update doesn't propagate to atSignTwo automatically
      await setAtSignOneAutoNotify(false);

      // Put a new value
      var verificationKeyNew = AtKey()
        ..key = 'verificationNumber'
        ..sharedWith = atSignTwo;
      var newValue = '9900';
      var newPutResult = await clientOne
          .put(verificationKeyNew, newValue);
      expect(newPutResult, true);

      // Sync the data to the remote secondary
      await E2ESyncService.getInstance()
          .syncData(clientOne.syncService);


      // As atSignTwo
      clientTwo = (await AtClientManager.getInstance()
          .setCurrentAtSign(atSignTwo, namespace,
              TestPreferences.getInstance().getPreference(atSignTwo))).atClient;

      // Sync - after this we still should have the old value
      await E2ESyncService.getInstance()
          .syncData(clientTwo.syncService);

      // get result with bypassCache set to false
      // should still return the initial value
      getResult = await clientTwo.get(getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = false);
      print('get result with bypass cache false $getResult');
      expect(getResult.value, initialValue);

      // get result with bypassCache set to true
      // should return the new value
      getResult = await clientTwo.get(getKey,
          getRequestOptions: GetRequestOptions()..bypassCache = true);
      print('get result with bypass cache true $getResult');
      expect(getResult.value, newValue);

      // Sync - after this we should now have the new value
      await E2ESyncService.getInstance()
          .syncData(clientTwo.syncService);

      // get Result with byPassCache set to false again
      // should also now return the new value, since cached value will have been updated with the
      // results of the remote lookup, and the cached value will have been synced to the client
      // Note: This will only work on server versions which have the fix, from version 3.0.29 onwards
      Version serverTwoVersion = await getVersion(clientTwo);
      if (serverTwoVersion >= Version(3, 0, 29)) {
        var getResultWithFalse = await clientTwo.get(
            getKey,
            getRequestOptions: GetRequestOptions()
              ..bypassCache = false);
        print('get result with bypass cache false $getResultWithFalse');
        expect(getResultWithFalse.value, newValue);
      }
    } finally {
      await setAtSignOneAutoNotify(true);
    }
  });
}
