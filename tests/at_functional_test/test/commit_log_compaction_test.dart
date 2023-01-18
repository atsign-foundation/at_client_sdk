import 'package:at_client/at_client.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

late AtClientManager atClientManager;
late String sharedWithAtSign;
AtCommitLog? atCommitLog;
String currentAtSign = '@alice🛠';
var preference = TestUtils.getPreference(currentAtSign);
String namespace = 'wavi';

Future<void> setUpMethod() async {
  atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(currentAtSign, namespace, preference);
  atClientManager.atClient.syncService.sync();
  // To setup encryption keys
  await setEncryptionKeys(currentAtSign, preference);
}

void main() {
  setUp(() async => await setUpMethod());

  test(
      'A test to verify commit log compaction during multiple updates of a key',
      () async {
    AtKey atKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(currentAtSign))
        .build();
    var value = '91878723456';
    // Insert the same for 5 times for the commit log compaction to have entries
    // of same key for multiple times.
    for (int i = 0; i < 5; i++) {
      await atClientManager.atClient.put(atKey, value);
      await Future.delayed(Duration(milliseconds: 2));
    }
    atCommitLog =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(currentAtSign);

    // Now, let the duplicate entries sync to the cloud secondary.
    // Client side commit log compaction removes the duplicate entries only
    // if they have been synced to the cloud secondary.
    var isSyncInProgress = true;
    atClientManager.atClient.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      print('Sync in progress...');
      await Future.delayed(Duration(milliseconds: 500));
    }

    Future<AtCompactionStats> compactionFuture =
        AtCompactionService.getInstance().executeCompaction(atCommitLog!);
    // TODO Do a bunch of other keystore operations (creates, updates, deletes) "while" the commitLog compaction is running

    await compactionFuture.then((atCompactionStats) {
      print(atCompactionStats);
      expect(
          atCompactionStats.postCompactionEntriesCount <
              atCompactionStats.preCompactionEntriesCount,
          true);
    });
  });

  test('A test to verify commit log compaction while multiple deletes',
      () async {
    AtKey atKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(currentAtSign))
        .build();
    var value = '91878723456';
    // Delete the same for 5 times for the commit log compaction to have entries
    // of same key for multiple times.
    await atClientManager.atClient.put(atKey, value);
    for (int i = 0; i < 5; i++) {
      await atClientManager.atClient.delete(atKey);
      await Future.delayed(Duration(milliseconds: 2));
    }
    atCommitLog =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(currentAtSign);

    // Now, let the duplicate entries sync to the cloud secondary.
    // Client side commit log compaction removes the duplicate entries only
    // if they have been synced to the cloud secondary.
    var isSyncInProgress = true;
    atClientManager.atClient.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      print('Sync in progress...');
      await Future.delayed(Duration(milliseconds: 500));
    }

    Future<AtCompactionStats> compactionFuture =
        AtCompactionService.getInstance().executeCompaction(atCommitLog!);
    await compactionFuture.then((atCompactionStats) {
      print(atCompactionStats);
      expect(
          atCompactionStats.postCompactionEntriesCount <
              atCompactionStats.preCompactionEntriesCount,
          true);
    });
  });

  test(
      'A test to verify commit log compaction should be same when there are no operations',
      () async {
    atCommitLog =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(currentAtSign);

    Future<AtCompactionStats> compactionFuture =
        AtCompactionService.getInstance().executeCompaction(atCommitLog!);

    await compactionFuture.then((atCompactionStats) {
      print(atCompactionStats);
      expect(
          atCompactionStats.postCompactionEntriesCount ==
              atCompactionStats.preCompactionEntriesCount,
          true);
    });
  });
}
