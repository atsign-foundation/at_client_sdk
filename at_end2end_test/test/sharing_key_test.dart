import 'dart:io';
import 'dart:math';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  var atSign1, atSign2;
  AtClientManager? atSign1AtClientManager, atSign2AtClientManager;

  setUp(() async {
    atSign1 = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atSign2 = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    atSign1AtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign1, 'me', TestUtils.getPreference(atSign1));
    //await TestUtils.setEncryptionKeys(atSign1);
    var isSyncInProgress = true;
    atSign1AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }

    atSign2AtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign2, 'me', TestUtils.getPreference(atSign2));
    //await TestUtils.setEncryptionKeys(atSign2);
    isSyncInProgress = true;
    atSign2AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  });
  test('Share a key to @atSign2 and lookup from @atSign2', () async {
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = atSign2;
    var lastNumber = Random().nextInt(10);
    // Appending a random number as a last number to generate a new phone number
    // for each run.
    var value = '+1 100 200 30$lastNumber';
    await AtClientManager.getInstance()
        .setCurrentAtSign(atSign1, 'me', TestUtils.getPreference(atSign1));
    var putResult = await atSign1AtClientManager?.atClient.put(phoneKey, value);
    expect(putResult, true);
    var isSyncInProgress = true;
    atSign1AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    await AtClientManager.getInstance()
        .setCurrentAtSign(atSign2, 'me', TestUtils.getPreference(atSign2));
    var getResult = await atSign2AtClientManager?.atClient.get(AtKey()
      ..key = 'phone'
      ..sharedBy = atSign1);
    expect(getResult?.value, value);
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 1)));

  test('Create a key to @atSign2 with ttr and verify @atSign2 has a cached_key',
      () async {
    await AtClientManager.getInstance()
        .setCurrentAtSign(atSign1, 'me', TestUtils.getPreference(atSign1));
    var verificationKey = AtKey()
      ..key = 'verificationNumber'
      ..sharedWith = atSign2
      ..metadata = (Metadata()
        ..ttr = 1000
        ..ccd = true
        ..ttl = 300000);
    var value = '0873';
    var putResult =
        await atSign1AtClientManager?.atClient.put(verificationKey, value);
    expect(putResult, true);
    var isSyncInProgress = true;
    atSign1AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    await AtClientManager.getInstance()
        .setCurrentAtSign(atSign2, 'me', TestUtils.getPreference(atSign2));
    isSyncInProgress = true;
    atSign2AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 5));
    }
    var getResult =
        await atSign2AtClientManager?.atClient.getKeys();
    print(getResult);
    expect(getResult?.contains('cached:$atSign2:verificationnumber.me$atSign1'), true);
    //Setting the timeout to prevent termination of test, since we have Future.delayed
    // for 30 Seconds.
  }, timeout: Timeout(Duration(minutes: 20)));

  tearDown(() async {
    var isExists = await Directory('test/hive').exists();
    if (isExists) {
      Directory('test/hive/').deleteSync(recursive: true);
    }
  });
}
