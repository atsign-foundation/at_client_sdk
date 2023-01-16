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

  test('A test to verify commit log compaction', () async {
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
    // Lets the duplicate entries sync to the cloud secondary.
    // Client side commit log compaction removes the duplicate entries that
    // are synced to the cloud secondary.
    var isSyncInProgress = true;
    atClientManager.atClient.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      print('Sync in progress...');
      await Future.delayed(Duration(milliseconds: 500));
    }
    AtCompactionStats atCompactionStats =
        await AtCompactionService.getInstance().executeCompaction(atCommitLog!);
    print(atCompactionStats);
    expect(
        atCompactionStats.postCompactionEntriesCount <
            atCompactionStats.preCompactionEntriesCount,
        true);
  });
}
