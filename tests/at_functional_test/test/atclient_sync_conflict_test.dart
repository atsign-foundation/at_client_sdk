import 'package:at_client/at_client.dart';
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
    atClientManager.atClient.syncService.addProgressListener(progressListener);
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

  /// The purpose of this test verify the following:
  /// 1. Updating a key with ttl 10ms to the cloud (Key becomes null after 10s in the server)
  /// 2. Updating the same key in the client with a non null value
  /// 3. Verifying that sync conflict is populated with no exception thrown
  test('server value is null', () async {
    AtSignLogger.root_level = 'info';
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener2();
    atClientManager.atClient.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    final remoteSecondary = atClient.getRemoteSecondary()!;
    final updateVerbBuilder = UpdateVerbBuilder()
      ..sharedBy = atSign
      ..atKey = 'test.wavi'
      ..ttl = 10
      ..value = 'randomvalue';
    await remoteSecondary.executeVerb(updateVerbBuilder);
    var testKey = AtKey()..key = 'test';
    await atClient.put(testKey, '123');
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

class MySyncProgressListener2 extends SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    bool conflictExists = false;
    for (var keyInfo in syncProgress.keyInfoList!) {
      if (keyInfo.key == 'test.wavi@alice🛠' &&
          keyInfo.syncDirection.toString() == 'SyncDirection.remoteToLocal') {
        final conflictInfo = keyInfo.conflictInfo;
        if (conflictInfo != null) {
          conflictExists = true;
          print('conflictInfo is $conflictInfo');
        }
      }
    }
    expect(conflictExists, true);
  }
}
