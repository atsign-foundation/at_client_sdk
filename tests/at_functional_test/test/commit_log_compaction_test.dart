import 'package:at_client/at_client.dart';
import 'package:test/test.dart';
import 'package:at_client/src/compaction/at_commit_log_compaction.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_client/src/preference/at_client_config.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

late AtClientManager atClientManager;
late String currentAtSign;
late String sharedWithAtSign;
late AtClient atClient;
late AtCommitLog atCommitLog;

Future<void> setUpMethod() async {
  currentAtSign = '@alice🛠';
  var preference = TestUtils.getPreference(currentAtSign);
  String namespace = 'wavi';

  // Override the "commitLogCompactionTimeIntervalInMins" to 1 minute
  AtClientConfig atClientConfig = AtClientConfig.getInstance()
    ..commitLogCompactionTimeIntervalInMins = 1;
  // Initialize the commit log
  atCommitLog = (await AtCommitLogManagerImpl.getInstance().getCommitLog(
      currentAtSign,
      enableCommitId: false,
      commitLogPath: preference.commitLogPath))!;
  // Get the secondaryPersistentStoreFactory Instance
  var secondaryPersistentStoreFactory =
      SecondaryPersistenceStoreFactory.getInstance()
          .getSecondaryPersistenceStore(currentAtSign);
  // Create the AtCompactionJob instance.
  AtCompactionJob atCompactionJob =
      AtCompactionJob(atCommitLog, secondaryPersistentStoreFactory!);

  var atClientCommitLogCompaction =
      AtClientCommitLogCompaction.create(currentAtSign, atCompactionJob);
  // Create AtClientImpl instance setting the atClientCommitLogCompaction
  // instance and AtClientConfig instance
  atClient = await AtClientImpl.create(currentAtSign, namespace, preference,
      atClientCommitLogCompaction: atClientCommitLogCompaction,
      atClientConfig: atClientConfig);

  AtServiceFactory atServiceFactory = AtServiceFactory()..atClient = atClient;
  atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign, 'me', preference,
      atServiceFactory: atServiceFactory);
  atClientManager.atClient.syncService.sync();
  // To setup encryption keys
  await setEncryptionKeys(currentAtSign, preference);
}

void main() {
  setUp(() async => await setUpMethod());

  test('A test to verify commit log compaction', () async {
    AtKey atKey = (AtKey.self('phone', namespace: 'wavi')
          ..sharedBy(currentAtSign))
        .build();
    var value = '91878723456';
    // Insert the same for 5 times for the commit log compaction to have entries
    // of same key for multiple times.
    await atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClient.put(atKey, value);
    int commitLogEntriesCountBeforeCompaction = atCommitLog.entriesCount();
    print(
        'Commit log entries count before compaction: $commitLogEntriesCountBeforeCompaction');
    // Wait for 1 minute + 12 seconds (random delay added in compaction job)for the compaction job
    // to complete.
    await Future.delayed(Duration(seconds: 72));
    int commitLogEntriesCountAfterCompaction = atCommitLog.entriesCount();
    print(
        'Commit log entries count after compaction: $commitLogEntriesCountAfterCompaction');
    expect(
        commitLogEntriesCountAfterCompaction <
            commitLogEntriesCountBeforeCompaction,
        true);
  }, timeout: Timeout(Duration(minutes: 2)));
}
