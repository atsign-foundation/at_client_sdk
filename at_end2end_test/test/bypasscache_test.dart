import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';
import 'package:at_client/at_client.dart';
import 'test_utils.dart';
import 'package:at_client/src/client/request_options.dart';

void main() {
  var currentAtSign, sharedWithAtSign;
  AtClientManager? currentAtSignClientManager, sharedWithAtSignClientManager;
  var namespace = 'wavi';

  setUpAll(() async {
    currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    sharedWithAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    // Create atClient instance for currentAtSign
    currentAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(
            currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    // Set Encryption Keys for currentAtSign
    await TestUtils.setEncryptionKeys(currentAtSign);
    var isSyncInProgress = true;
    currentAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    // Create atClient instance for atSign2
    sharedWithAtSignClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(sharedWithAtSign, namespace,
            TestUtils.getPreference(sharedWithAtSign));
    // Set Encryption Keys for sharedWithAtSign
    await TestUtils.setEncryptionKeys(sharedWithAtSign);
    isSyncInProgress = true;
    sharedWithAtSignClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  });

  /// The purpose of this test is to verify the following:
  /// 1. Share a key from atsign_1 to atsign_2 with ttr, with autoNotify:true
  /// 2. lookup from atsign_2 returns the correct value
  /// 3.  Set the autoNotify to false using the config verb 
  /// 4. Update the existing key to a new value 
  /// 4. lookup with bypass_cache set to true should return the updated value
  /// 5. lookup with bypass_cache set to false should return the old value
   test('bypass cache test',
      () async {
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    var verificationKey = AtKey()
      ..key = 'verificationnumber'
      ..sharedWith = sharedWithAtSign
      ..metadata = (Metadata()
        ..ttr = 1000);
    var oldValue = '0873';
    // upating the key with value
    var putResult =
        await currentAtSignClientManager?.atClient.put(verificationKey, oldValue);
    expect(putResult, true);
    await refresh(currentAtSignClientManager!);
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    await refresh(sharedWithAtSignClientManager!);
    var getKey = AtKey() 
    ..key = 'verificationnumber'
    ..sharedBy =currentAtSign;
    var getResult = await sharedWithAtSignClientManager?.atClient.get(getKey);
    expect(getResult?.value, oldValue);
    print('get Result is $getResult'); 
    // Setting currentAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, TestUtils.getPreference(currentAtSign));
    // set auto notify to false  
    var configResult = await currentAtSignClientManager?.atClient.getRemoteSecondary()!.executeCommand('config:set:autoNotify=false\n', auth: true);
    expect(configResult, contains('data:ok'));
    // adding a delay for 2 seconds till the config value gets updated
    await Future.delayed(Duration(seconds: 3));
    // Updating the same key with a new value
    var verificationKeyNew = AtKey()
      ..key = 'verificationnumber'
      ..sharedWith = sharedWithAtSign;
    var newValue = '9900';
    var newPutResult =
        await currentAtSignClientManager?.atClient.put(verificationKeyNew, newValue);
    expect(newPutResult, true);
    await refresh(currentAtSignClientManager!);
    // Setting sharedWithAtSign atClient instance to context.
    await AtClientManager.getInstance().setCurrentAtSign(
        sharedWithAtSign, namespace, TestUtils.getPreference(sharedWithAtSign));
    await refresh(sharedWithAtSignClientManager!);
    //  get result with bypassCache set to true
    // should return the newly updated value
    getResult = await sharedWithAtSignClientManager?.atClient.get(getKey, getRequestOptions: GetRequestOptions()..bypassCache = true);
    print('get result with bypass cache true $getResult');
    expect(getResult?.value, newValue);
    // get Result with byPassCache set to false
    // should return the old value
    // adding a delay
    await Future.delayed(Duration(seconds: 3));
    var getResultWithFalse = await sharedWithAtSignClientManager?.atClient.get(getKey, getRequestOptions: GetRequestOptions()..bypassCache = false);
    print('get result with bypass cache false $getResultWithFalse');
    expect(getResultWithFalse?.value, oldValue);
    //  reset the autoNotify to false
    configResult = await currentAtSignClientManager?.atClient
        .getRemoteSecondary()!
        .executeCommand('config:set:autoNotify=true\n', auth: true);
    expect(configResult, contains('data:ok'));
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 5)));
}

Future<void> refresh(AtClientManager atClientManager) async {
  var isSyncInProgress = true;
    atClientManager.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    } 
}