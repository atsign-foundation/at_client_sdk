import 'package:at_client/at_client.dart';
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
          .getRemoteSecondary()!
          .executeCommand('update:$atsign:key$i$atsign value$i\n', auth: true);
      expect(putResult, startsWith('data:'));
      print('putResult $putResult');
    }
    expect(await atClient.syncService.isInSync(), false);
    atClient.syncService.sync();
    await Future.delayed(Duration(seconds: 10));
  });

  test('Parallel sync calls to remote from local', () async {
    var atsign = '@sitaram';
    var preference = TestUtil.getPreferenceLocal();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', preference);
    var atClient = atClientManager.atClient;
    var syncService = atClient.syncService;
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
    syncService.sync();
    syncService.sync();
    await Future.delayed(Duration(seconds: 10));
  });
}

void onError(syncResult) {
  print(syncResult);
}
