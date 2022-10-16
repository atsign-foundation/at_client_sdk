import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/sync_progress_listener.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() async {
  test('notify updating of a key to sharedWith atSign - using await', () async {
    AtSignLogger.root_level = 'info';
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener();
    atClientManager.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    final remoteSecondary = atClient.getRemoteSecondary()!;
    final updateVerbBuilder = UpdateVerbBuilder()
      ..sharedBy = atSign
      ..atKey = 'phone_0.wavi' //conflicting key
      ..value = 'sMBnYFctMOg+lqX67ah9UA=='; //encrypted value of 4
    await remoteSecondary.executeVerb(updateVerbBuilder);
    //
    for (var i = 0; i < 5; i++) {
      var phoneKey = AtKey()..key = 'phone_$i';
      var value = '$i';
      await atClient.put(phoneKey, value);
    }
    await Future.delayed(Duration(seconds: 10));
  });
}

class MySyncProgressListener extends SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    bool conflictExists = false;
    for (var keyInfo in syncProgress.keyInfoList!) {
      if (keyInfo.key == 'phone_0.wavi@alice🛠' &&
          keyInfo.syncDirection.toString() == 'SyncDirection.remoteToLocal') {
        final conflictInfo = keyInfo.conflictInfo;
        if (conflictInfo != null &&
            conflictInfo.remoteValue == '4' &&
            conflictInfo.localValue == '0') {
          conflictExists = true;
        }
      }
    }
    expect(conflictExists, true);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));
    expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
  }
}
