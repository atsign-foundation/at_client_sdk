import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  test('sync from remote to local', () async {
    var atsign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    var syncService = SyncService(atClient!);
    // // To setup encryption keys
    // await setEncryptionKeys(atsign, preference);
    // Adding 10 keys to remote secondary
    for (var i = 0; i < 30; i++) {
      var putResult = await atClient
          .getRemoteSecondary()!
          .executeCommand('update:$atsign:key$i$atsign value$i\n', auth: true);
      expect(putResult, startsWith('data:'));
      print('putResult $putResult');
    }
    expect(await syncService.isInSync(), false);
    syncService.sync(onSuccess, onError);
    await Future.delayed(Duration(seconds: 10));
  });

  test('Parallel sync calls to remote from local', () async {
    var atsign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    var syncService = SyncService(atClient!);
    // // To setup encryption keys
    // await setEncryptionKeys(atsign, preference);
    // Adding 10 keys to remote secondary
    for (var i = 0; i < 30; i++) {
      var putResult = await atClient
          .getRemoteSecondary()!
          .executeCommand('update:$atsign:key$i$atsign value$i\n', auth: true);
      expect(putResult, startsWith('data:'));
      print('putResult $putResult');
    }
    expect(await syncService.isInSync(), false);
    syncService.sync(onSuccess, onError);
    syncService.sync(onSuccess, (syncResult) {
      expect(syncResult.syncStatus, SyncStatus.failure);
      expect(syncResult.atClientException.errorMessage,
          'Sync-InProgress. Cannot start a new sync process');
    });
    await Future.delayed(Duration(seconds: 10));
  });

  test('Socket close when sync in-progress', () async {
    var atsign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl.getClient(atsign);
    var syncService = SyncService(atClient!);
    // // To setup encryption keys
    // await setEncryptionKeys(atsign, preference);
    // Adding 10 keys to remote secondary
    for (var i = 0; i < 1000; i++) {
      var putResult = await atClient
          .getRemoteSecondary()!
          .executeCommand('update:$atsign:key$i$atsign value$i\n', auth: true);
      expect(putResult, startsWith('data:'));
      print('putResult $putResult');
    }
    expect(await syncService.isInSync(), false);
    syncService.sync(onSuccess, (){
      print('Inside error callback');
      syncService.sync(onSuccess, onError);
    });
    // Force close the socket.
    await syncService.remoteSecondary.atLookUp.close();
    print('Connection closed');
    print(await syncService.isInSync());
    expect(await syncService.isInSync(), false);
    await Future.delayed(Duration(minutes: 1));
  },timeout: Timeout(Duration(seconds: 200)));
}

void onSuccess(syncResult) {
  expect(syncResult.syncStatus, SyncStatus.success);
}

void onError(syncResult) {
  print(syncResult);
}

// AtClientPreference getAlicePreference(String atsign) {
//   var preference = AtClientPreference();
//   preference.hiveStoragePath = 'test/hive/client';
//   preference.commitLogPath = 'test/hive/client/commit';
//   preference.isLocalStoreRequired = true;
//   preference.syncStrategy = SyncStrategy.IMMEDIATE;
//   preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
//   preference.rootDomain = 'vip.ve.atsign.zone';
//   return preference;
// }
