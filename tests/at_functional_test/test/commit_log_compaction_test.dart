import 'package:at_client/at_client.dart';
import 'package:at_client/src/preference/at_client_config.dart';
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
  // Override the "commitLogCompactionTimeIntervalInMins" to 1 minute
  AtClientConfig.getInstance()
    .commitLogCompactionTimeIntervalInMins = 1;
  atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
      currentAtSign, namespace, preference);
  atClientManager.atClient.syncService.sync();
  // To setup encryption keys
  await setEncryptionKeys(currentAtSign, preference);
}

void main() {
  setUp(() async => await setUpMethod());

  test('A test to verify commit log compaction', () async {
    AtKey atKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(currentAtSign))
        .build();
    var value = '91878723456';
    // Insert the same for 5 times for the commit log compaction to have entries
    // of same key for multiple times.
    await atClientManager.atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClientManager.atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClientManager.atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClientManager.atClient.put(atKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await atClientManager.atClient.put(atKey, value);
    atCommitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(currentAtSign);
    int commitLogEntriesCountBeforeCompaction = atCommitLog!.entriesCount();
    print(
        'Commit log entries count before compaction: $commitLogEntriesCountBeforeCompaction');
    // Wait for 1 minute + 12 seconds (random delay added in compaction job)for the compaction job
    // to complete.
    await Future.delayed(Duration(seconds: 72));
    int commitLogEntriesCountAfterCompaction = atCommitLog!.entriesCount();
    print(
        'Commit log entries count after compaction: $commitLogEntriesCountAfterCompaction');
    expect(
        commitLogEntriesCountAfterCompaction <
            commitLogEntriesCountBeforeCompaction,
        true);
  }, timeout: Timeout(Duration(minutes: 2)));
}
