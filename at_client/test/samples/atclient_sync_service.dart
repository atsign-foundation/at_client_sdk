import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('sync from remote to local', () async {
    var atsign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    // // To setup encryption keys
    // await setEncryptionKeys(atsign, preference);
    // Adding 10 keys to remote secondary
    for (var i = 0; i < 30; i++) {
      var putResult = await atClient
          .getRemoteSecondary()
          .executeCommand('update:$atsign:key$i$atsign value$i\n', auth: true);
      expect(putResult, startsWith('data:'));
      print('putResult $putResult');
    }
    expect(await atClientManager.syncService.isInSync(), false);
    atClientManager.syncService.sync(onDone: onSuccess);
    await Future.delayed(Duration(seconds: 10));
  });

  test('Parallel sync calls to remote from local', () async {
    var atsign = '@sitaram';
    var preference = TestUtil.getPreferenceLocal();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    var syncService = atClientManager.syncService;
    // // To setup encryption keys
    // await setEncryptionKeys(atsign, preference);
    // Adding 10 keys to remote secondary
    for (var i = 0; i < 30; i++) {
      var putResult = await atClient
          .getRemoteSecondary()
          .executeCommand('update:$atsign:key$i$atsign value$i\n', auth: true);
      expect(putResult, startsWith('data:'));
      print('putResult $putResult');
    }
    expect(await syncService.isInSync(), false);
    syncService.sync(onDone: (syncResult) async {
      var isInSync = await syncService.isInSync();
      expect(isInSync, true);
      print('Success: $syncResult : isInSync: $isInSync');
      expect(syncResult.syncStatus, SyncStatus.success);
    });
    syncService.sync(onDone: onSuccess);
    await Future.delayed(Duration(seconds: 10));
  });
}

void onSuccess(syncResult) async {
  print('Success: $syncResult');
  expect(syncResult.syncStatus, SyncStatus.success);
}

void onError(syncResult) {
  print(syncResult);
}
