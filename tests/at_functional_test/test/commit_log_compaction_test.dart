import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

late AtClientManager atClientManager;
late String sharedWithAtSign;
AtCommitLog? atCommitLog;
late String currentAtSign;
var preference = TestUtils.getPreference(currentAtSign);
String namespace = 'wavi';

Future<void> setUpMethod() async {
  currentAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  atClientManager = await TestUtils.initAtClient(currentAtSign, namespace);
  // Stopping the compaction job to prevent the compaction running in background.
  await atClientManager.atClient.stopCompactionJob();
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
    // Insert the same key for multiple times for the commit log compaction to have duplicate entries
    for (int i = 0; i < 500; i++) {
      await atClientManager.atClient.put(atKey, value);
      await Future.delayed(Duration(milliseconds: 2));
    }
    atCommitLog =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(currentAtSign);

    // Now, let the duplicate entries sync to the cloud secondary.
    // Client side commit log compaction removes the duplicate entries only
    // if they have been synced to the cloud secondary.
    await FunctionalTestSyncService.getInstance()
        .syncData(atClientManager.atClient.syncService);
    // Start the compaction job in async mode
    Future<AtCompactionStats> compactionFuture =
        AtCompactionService.getInstance().executeCompaction(atCommitLog!);
    // While the compaction job runs; create, update and delete a key and let the
    // sync service trigger.
    AtKey mobileAtKey = (AtKey.self('mobile', namespace: namespace)
          ..sharedBy(currentAtSign))
        .build();
    value = '9187872345';
    // Appending "i" to the value to have different value for each time a key is
    // inserted
    for (int i = 0; i < 2; i++) {
      await atClientManager.atClient.put(mobileAtKey, '$value$i');
      await Future.delayed(Duration(milliseconds: 2));
    }
    await atClientManager.atClient.delete(mobileAtKey);
    for (int i = 0; i < 5; i++) {
      await atClientManager.atClient.put(mobileAtKey, value);
      await Future.delayed(Duration(milliseconds: 2));
    }
    // Now, let the duplicate entries sync to the cloud secondary.
    // Client side commit log compaction removes the duplicate entries only
    // if they have been synced to the cloud secondary.
    await FunctionalTestSyncService.getInstance()
        .syncData(atClientManager.atClient.syncService);

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
    await FunctionalTestSyncService.getInstance()
        .syncData(atClientManager.atClient.syncService);

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
