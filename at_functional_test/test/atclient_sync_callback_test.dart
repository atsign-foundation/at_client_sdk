import 'package:at_client/src/listener/sync_progress_listener.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/service/sync/sync_status.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() {
  test('notify updating of a key to sharedWith atSign - using await', () async {
    AtSignLogger.root_level = 'finest';
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener();
    atClientManager.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // phone.me@alice🛠
    for (var i = 0; i < 5; i++) {
      var phoneKey = AtKey()..key = 'phone_$i';
      var value = '$i';
      var result = await atClient.put(phoneKey, value);
      print(result);
    }
    await Future.delayed(Duration(seconds: 10));
  });
}

class MySyncProgressListener extends SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    print('received sync progress: $syncProgress');
    expect(syncProgress.syncStatus, SyncStatus.success);
  }
}
