import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/sync_manager.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

void main() {
  group('A group of sync util tests', () {
    test('sync util check pkam private key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSkipSync(AT_PKAM_PRIVATE_KEY);
      expect(isSyncRequired, true);
    });
    test('sync util check pkam public key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSkipSync(AT_PKAM_PUBLIC_KEY);
      expect(isSyncRequired, true);
    });

    test('sync util check encryption private key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSkipSync(AT_ENCRYPTION_PRIVATE_KEY);
      expect(isSyncRequired, true);
    });

    test('sync util check encryption private key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSkipSync(AT_ENCRYPTION_PUBLIC_KEY);
      expect(isSyncRequired, false);
    });

    test('sync util check normal key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSkipSync('phone@bob');
      expect(isSyncRequired, false);
    });

    test('test in sync - no commits on local and server', () {
      var isInSync = SyncUtil.isInSync(null, null, null);
      expect(isInSync, true);
    });

    test('test in sync - uncommitted entries in local and commit ids are null',
            () {
          var entries = <CommitEntry>[];
          var entry =
          CommitEntry('public:phone@alice', CommitOp.UPDATE, DateTime.now());
          entries.add(entry);
          var isInSync = SyncUtil.isInSync(entries, null, null);
          expect(isInSync, false);
        });

    test(
        'test in sync - NO uncommitted entries in local and server commit id > local commit id',
            () {
          var isInSync = SyncUtil.isInSync(null, 1, 5);
          expect(isInSync, false);
        });

    test(
        'test in sync - uncommitted entries in local commit id > server commit id',
        () {
      var entries = <CommitEntry>[];
      var entry =
          CommitEntry('public:phone@alice', CommitOp.UPDATE, DateTime.now());
      entries.add(entry);
      var isInSync = SyncUtil.isInSync(entries, 5, 1);
      expect(isInSync, false);
    });
  });

  group('a group of hive related test cases', () {
    var atSign = '@alice';
    var preference;
    setUp(() async => preference = await setUpFunc(atSign));
    test('test in sync - syncLocal', () async {
      var commitEntryData = {
        'atKey': 'public:publickey@responsibleplum',
        'operation': '+',
        'opTime': '2021-03-08 20:03:15.278',
        'commitId': 0,
        'value':
            'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ#8AM\$IIBCgKCAQEAlGeVHT5LZbBQ+/GKi8eymOXsCpQ/0AkgQ16SEgysi47'
      };
      var atClient = await AtClientImpl.getClient(atSign);
      var syncManager = SyncManager(atSign);

      syncManager.init(atSign, preference, atClient.getRemoteSecondary(),
          atClient.getLocalSecondary());
      await syncManager.syncLocal(commitEntryData);
      var atCommitLog =
          await AtCommitLogManagerImpl.getInstance().getCommitLog(atSign);
      var commitEntry = atCommitLog.lastSyncedEntry();
      expect(commitEntryData['atKey'], commitEntry.atKey);
      expect(CommitOp.UPDATE_ALL, commitEntry.operation);
      expect(commitEntryData['commitId'], commitEntry.commitId);
    });
    tearDown(() async => tearDownFunc());
  });
}

Future<AtClientPreference> setUpFunc(String atSign) async {
  var preference = AtClientPreference()
    ..isLocalStoreRequired = true
    ..hiveStoragePath = '${Directory.current.path}/test/hive/client/'
    ..commitLogPath = '${Directory.current.path}/test/hive/client/commit';
  await AtClientImpl.createClient(atSign, 'me', preference);
  return preference;
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}
