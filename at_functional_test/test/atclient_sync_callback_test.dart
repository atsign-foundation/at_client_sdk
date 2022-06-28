import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/sync_progress_listener.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

List? keyList;

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
      await atClient.put(phoneKey, value);
    }
    await Future.delayed(Duration(seconds: 10));
  });

  test('delete of a key to sharedWith atSign - using await', () async {
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
    var phoneKey = AtKey()..key = 'number';
    await atClient.delete(phoneKey);
    await Future.delayed(Duration(seconds: 10));
  });

  test('Verifying keyname exists in key info list', () async {
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
    // username.wavi@alice🛠
    var usernameKey = AtKey()..key = 'username';
    var value = 'alice123';
    await atClient.put(usernameKey, value);
    await Future.delayed(Duration(seconds: 10));
    print('keylist is $keyList');
    var _key = keyList?.where((ele) => ele.key.contains('username'));
    expect(_key != null || _key!.isNotEmpty, true);
  });

  test('Verifying sync progress - local ahead', () async {
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
    // twitter.me@alice🛠
    var twitterKey = AtKey()..key = 'twitter';
    var value = 'alice_A';
    await atClient.put(twitterKey, value);
    await Future.delayed(Duration(seconds: 10));
  });

  test('Verifying sync progress - server ahead', () async {
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
    // username.me@alice🛠
    var value = 'alice_1231';
    var updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = 'fb_username'
      ..sharedBy = atSign
      ..isPublic = true
      ..value = value;
    var updateResponse =
        await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
    expect(updateResponse.isNotEmpty, true);
    await Future.delayed(Duration(seconds: 10));
  });
}

class MySyncProgressListener extends SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    print('received sync progress: $syncProgress');
    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));
    expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
    keyList = syncProgress.keyInfoList;
  }
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}
