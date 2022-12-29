import 'dart:async';
import 'dart:io';

import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:uuid/uuid.dart';
import 'set_encryption_keys.dart';
import 'test_utils.dart';

void main() {
  var uniqueId = Uuid().v4();
  test('notify updating of a key to sharedWith atSign - using await', () async {
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener();
    atClientManager.atClient.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // phone.me@alice🛠
    for (var i = 0; i < 5; i++) {
      var phoneKey = AtKey()..key = 'phone-$uniqueId-$i';
      var value = '$i';
      await atClient.put(phoneKey, value);
    }
    progressListener.streamController.stream
        .listen(expectAsync1((SyncProgress syncProgress) {
      print('sync progress status : $syncProgress');
      expect(syncProgress.syncStatus, SyncStatus.success);
      expect(syncProgress.keyInfoList, isNotEmpty);
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
      expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
      syncProgress.keyInfoList?.forEach((keyInfo) {
        if (keyInfo.key.startsWith('phone-$uniqueId')) {
          expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
          expect(keyInfo.syncDirection, SyncDirection.localToRemote);
        }
      });
      atClientManager.atClient.syncService
          .removeProgressListener(progressListener);
    }));
  });

  test('delete of a key to sharedWith atSign - using await', () async {
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener();
    atClientManager.atClient.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()..key = 'number-$uniqueId';
    await atClient.delete(phoneKey);
    progressListener.streamController.stream
        .listen(expectAsync1((SyncProgress syncProgress) {
      expect(syncProgress.syncStatus, SyncStatus.success);
      expect(syncProgress.keyInfoList, isNotEmpty);
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
      expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
      syncProgress.keyInfoList?.forEach((keyInfo) {
        if (keyInfo.key.startsWith('number-$uniqueId')) {
          expect(keyInfo.commitOp, CommitOp.DELETE);
          expect(keyInfo.syncDirection, SyncDirection.localToRemote);
        }
      });
      atClientManager.atClient.syncService
          .removeProgressListener(progressListener);
    }));
  });

  test('Verifying keyname exists in key info list', () async {
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener();
    atClientManager.atClient.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // username.wavi@alice🛠
    var usernameKey = AtKey()..key = 'username-$uniqueId';
    var value = 'alice123';
    await atClient.put(usernameKey, value);
    progressListener.streamController.stream
        .listen(expectAsync1((SyncProgress syncProgress) {
      expect(syncProgress.syncStatus, SyncStatus.success);
      expect(syncProgress.keyInfoList, isNotEmpty);
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
      expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
      syncProgress.keyInfoList?.forEach((keyInfo) {
        if(keyInfo.key.contains('username-$uniqueId')) {
          expect(keyInfo.syncDirection, SyncDirection.localToRemote);
          expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
        }
      });
      atClientManager.atClient.syncService
          .removeProgressListener(progressListener);
    }));
  });

  test('Verifying sync progress - local ahead', () async {
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener();
    atClientManager.atClient.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // twitter.me@alice🛠
    var twitterKey = AtKey()..key = 'twitter-$uniqueId';
    var value = 'alice_A';
    await atClient.put(twitterKey, value);

    progressListener.streamController.stream
        .listen(expectAsync1((SyncProgress syncProgress) {
      expect(syncProgress.syncStatus, SyncStatus.success);
      expect(syncProgress.keyInfoList, isNotEmpty);
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
      expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
      syncProgress.keyInfoList?.forEach((keyInfo) {
        if(keyInfo.key.contains('twitter-$uniqueId')) {
          expect(keyInfo.syncDirection, SyncDirection.localToRemote);
          expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
        }
      });
      atClientManager.atClient.syncService
          .removeProgressListener(progressListener);
    }));
  });

  test('Verifying sync progress - server ahead', () async {
    final atSign = '@alice🛠';
    var preference = TestUtils.getPreference(atSign);
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    final progressListener = MySyncProgressListener();
    atClientManager.atClient.syncService.addProgressListener(progressListener);
    final atClient = atClientManager.atClient;
    // To setup encryption keys
    await setEncryptionKeys(atSign, preference);
    // username.me@alice🛠
    var value = 'alice_1231';
    var updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = 'fb_username-$uniqueId'
      ..sharedBy = atSign
      ..isPublic = true
      ..value = value;
    var updateResponse =
        await atClient.getRemoteSecondary()!.executeVerb(updateVerbBuilder);
    expect(updateResponse.isNotEmpty, true);
    progressListener.streamController.stream
        .listen(expectAsync1((SyncProgress syncProgress) {
      expect(syncProgress.syncStatus, SyncStatus.success);
      expect(syncProgress.keyInfoList, isNotEmpty);
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
      expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
      syncProgress.keyInfoList?.forEach((keyInfo) {
        if(keyInfo.key.contains('fb_username-$uniqueId') ){
          expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
          expect(keyInfo.syncDirection, SyncDirection.remoteToLocal);
        }
      });
      atClientManager.atClient.syncService
          .removeProgressListener(progressListener);
    }));
  });
  tearDown(() async => await tearDownFunc());
}

class MySyncProgressListener extends SyncProgressListener {
  StreamController<SyncProgress> streamController =
      StreamController<SyncProgress>();

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    streamController.add(syncProgress);
  }
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}
