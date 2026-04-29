// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_progress_listener.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'test_utils.dart';

void main() {
  late AtClientManager atClientManager;
  late String atSign;
  var uniqueId = Uuid().v4();
  String namespace = 'wavi';
  // final logger = AtSignLogger(' atclient_sync_callback_test.dart ');

  FunctionalTestSyncService testSyncSvc =
      FunctionalTestSyncService.getInstance();

  setUp(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    var preference = TestUtils.getPreference(atSign);
    preference.syncBatchSize = 15;
    atClientManager =
        await TestUtils.initAtClient(atSign, namespace, preference: preference);
    await testSyncSvc.syncData();
  });

  tearDown(() async {
    atClientManager.atClient.syncService.removeAllProgressListeners();
  });

  test('notify updating of a key to sharedWith atSign - using await', () async {
    // phone.me@alice🛠
    for (var i = 0; i < 5; i++) {
      var phoneKey = AtKey()..key = 'phone-$uniqueId-$i';
      var value = '$i';
      await atClientManager.atClient.put(phoneKey, value);
    }

    MySyncProgressListener pl = MySyncProgressListener(true);
    atClientManager.atClient.syncService.addProgressListener(pl);
    await testSyncSvc.syncData();

    Completer<SyncProgress> progress = Completer();
    pl.streamController.stream.listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;
    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));
    expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
    bool keyInfoFound = false;
    syncProgress.keyInfoList?.forEach((keyInfo) {
      if (keyInfo.key.startsWith('phone-$uniqueId')) {
        keyInfoFound = true;
        expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
        expect(keyInfo.syncDirection, SyncDirection.localToRemote);
      }
    });
    expect(keyInfoFound, true);
  });

  test('delete of a key to sharedWith atSign - using await', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()..key = 'number-$uniqueId';
    await atClientManager.atClient.delete(phoneKey);

    MySyncProgressListener pl = MySyncProgressListener(true);
    atClientManager.atClient.syncService.addProgressListener(pl);
    await testSyncSvc.syncData();

    Completer<SyncProgress> progress = Completer();
    pl.streamController.stream.listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;
    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));
    expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
    bool keyInfoFound = false;
    syncProgress.keyInfoList?.forEach((keyInfo) {
      if (keyInfo.key.startsWith('number-$uniqueId')) {
        keyInfoFound = true;
        expect(keyInfo.commitOp, CommitOp.DELETE);
        expect(keyInfo.syncDirection, SyncDirection.localToRemote);
      }
    });
    expect(keyInfoFound, true);
  });

  test('Verifying keyname exists in key info list', () async {
    // username.wavi@alice🛠
    var usernameKey = AtKey.fromString('username-$uniqueId.$namespace$atSign');
    var value = 'alice123';
    await atClientManager.atClient.put(usernameKey, value);

    MySyncProgressListener pl = MySyncProgressListener(true);
    atClientManager.atClient.syncService.addProgressListener(pl);
    await testSyncSvc.syncData();

    Completer<SyncProgress> progress = Completer();
    pl.streamController.stream.listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;

    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));
    expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
    bool keyInfoFound = false;
    syncProgress.keyInfoList?.forEach((keyInfo) {
      if (keyInfo.key.contains('username-$uniqueId')) {
        keyInfoFound = true;
        expect(keyInfo.syncDirection, SyncDirection.localToRemote);
        expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
      }
    });
    expect(keyInfoFound, true);
  });

  test('Verifying sync progress - local ahead', () async {
    // Put one key, and sync it
    // We expect to receive a SyncProgress:
    // - whose status is 'success'
    // - where localCommitId == serverCommitId
    // - where localCommitId > localCommitId before sync
    // - which includes KeyInfo for the key we put, localToRemote

    // twitter.me@alice🛠
    var twitterKey = AtKey.fromString('twitter-$uniqueId.$namespace$atSign');
    var value = 'alice_A';
    await atClientManager.atClient.put(twitterKey, value);

    MySyncProgressListener pl = MySyncProgressListener(true);
    atClientManager.atClient.syncService.addProgressListener(pl);
    await testSyncSvc.syncData();

    Completer<SyncProgress> progress = Completer();
    pl.streamController.stream.listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;
    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));
    expect(syncProgress.localCommitId, equals(syncProgress.serverCommitId));
    bool keyInfoFound = false;
    syncProgress.keyInfoList?.forEach((keyInfo) {
      if (keyInfo.key.contains('twitter-$uniqueId')) {
        keyInfoFound = true;
        expect(keyInfo.syncDirection, SyncDirection.localToRemote);
        expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
      }
    });
    expect(keyInfoFound, true);
  });

  test('Verifying sync progress - server ahead', () async {
    // username.me@alice🛠
    var value = 'alice_1231';
    var updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'fb_username-$uniqueId'
        ..sharedBy = atSign
        ..metadata = (Metadata()..isPublic = true))
      ..value = value;
    var updateResponse = await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(updateVerbBuilder);
    expect(updateResponse.isNotEmpty, true);

    MySyncProgressListener pl = MySyncProgressListener(true);
    atClientManager.atClient.syncService.addProgressListener(pl);
    await testSyncSvc.syncData();

    Completer<SyncProgress> progress = Completer();
    pl.streamController.stream.listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;
    expect(syncProgress.syncStatus, SyncStatus.success);
    // If localCommitIdBeforeSync and localCommitId (local commitId after sync)
    // are equal, it means there is not nothing to sync. So do not assert below conditions.
    // The sync callback gets triggered twice, and the below conditions will be asserted
    // on either of the sync process callback.
    if (syncProgress.localCommitIdBeforeSync != syncProgress.localCommitId) {
      expect(syncProgress.keyInfoList, isNotEmpty);
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
      bool keyInfoFound = false;
      syncProgress.keyInfoList?.forEach((keyInfo) {
        if (keyInfo.key.contains('fb_username-$uniqueId')) {
          keyInfoFound = true;
          expect(keyInfo.syncDirection, SyncDirection.remoteToLocal);
          expect(keyInfo.commitOp, CommitOp.UPDATE_ALL);
        }
      });
      expect(keyInfoFound, true);
    }
  });

  test(
      'A test to verify latest commit entry is updated when same key is updated and deleted',
      () async {
    var uniqueId = Uuid().v4();
    final atSign = '@alice🛠';
    final sharedWithAtSign = '@bob🛠';
    String namespace = 'wavi';

    AtKey firstAtKey = (AtKey.shared('firstKey-$uniqueId',
            namespace: namespace, sharedBy: atSign)
          ..sharedWith(sharedWithAtSign))
        .build();
    AtKey secondAtKey = (AtKey.shared('secondKey-$uniqueId',
            namespace: namespace, sharedBy: atSign)
          ..sharedWith(sharedWithAtSign))
        .build();

    await AtClientManager.getInstance().atClient.put(firstAtKey, 'value-1');
    await AtClientManager.getInstance().atClient.put(secondAtKey, 'value-2');
    await AtClientManager.getInstance().atClient.delete(firstAtKey);

    MySyncProgressListener pl = MySyncProgressListener(true);
    atClientManager.atClient.syncService.addProgressListener(pl);
    await testSyncSvc.syncData();

    Completer<SyncProgress> progress = Completer();
    pl.streamController.stream.listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;

    expect(syncProgress.syncStatus, SyncStatus.success);

    // Get Commit Entries from server
    var serverCommitEntries = await AtClientManager.getInstance()
        .atClient
        .getRemoteSecondary()
        ?.executeCommand('stats:15:$uniqueId\n', auth: true);
    var serverCommitLogMap = jsonDecode(
        jsonDecode(serverCommitEntries!.replaceAll('data:', ''))[0]['value']);

    //Get Commit Entries from local
    var atCommitLog = (AtClientManager.getInstance().atClient as AtClientImpl)
        .persistenceBundle!
        .commitLog;
    var localCommitEntries = await atCommitLog.commitLogKeyStore.toMap();

    for (var commitEntry in localCommitEntries.values) {
      if (commitEntry.atKey == firstAtKey.toString()) {
        expect(
            commitEntry.commitId, serverCommitLogMap[firstAtKey.toString()][0]);
        expect(commitEntry.operation.name,
            serverCommitLogMap[firstAtKey.toString()][1]);
      }
      if (commitEntry.atKey == secondAtKey.toString()) {
        expect(commitEntry.commitId,
            serverCommitLogMap[secondAtKey.toString()][0]);
        expect(commitEntry.operation.name,
            serverCommitLogMap[secondAtKey.toString()][1]);
      }
    }
  });
}
