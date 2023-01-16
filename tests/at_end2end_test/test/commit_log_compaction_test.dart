import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';

late String firstAtSign;
late String secondAtSign;

late AtClientManager firstAtClientManager;
late AtClientManager secondAtClientManager;

AtCommitLog? firstAtSignAtCommitLog;
AtCommitLog? secondAtSignAtCommitLog;

final namespace = 'wavi';

/// The purpose of this test case to verify the commit log compaction job on the first AtSign stops
/// on the switch atSign event and commit log compaction job starts on the second AtSign.

Future<void> setUpMethod() async {
  firstAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  secondAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
  // Initialize the atSigns which
  // 1. Initializes the local storage
  // 2. sets the encryption key pair
  // 3. Starts the notification, sync and compaction service.
  await TestSuiteInitializer.getInstance()
      .testInitializer(firstAtSign, namespace);
  await TestSuiteInitializer.getInstance()
      .testInitializer(secondAtSign, namespace);
}

void main() {
  setUp(() async => await setUpMethod());

  test('A test to verify commit log compaction on switch atSign event',
      () async {
    firstAtClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        firstAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(firstAtSign));
    firstAtClientManager.atClient.syncService.sync();
    // Initialize AtClientManager for second AtSign
    secondAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(secondAtSign, namespace,
            TestPreferences.getInstance().getPreference(secondAtSign));
    secondAtClientManager.atClient.syncService.sync();

    expect(
        AtClientImpl
            .atClientInstanceMap[secondAtSign].atClientCommitLogCompaction
            ?.isCompactionJobRunning(),
        true);
  });

  test(
      'A test to verify commit log compaction job removes the duplicate entries from commit log',
      () async {
    var atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        secondAtSign,
        namespace,
        TestPreferences.getInstance().getPreference(secondAtSign));
    var atKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(secondAtSign))
        .build();
    var value = '91878723456';
    // Insert the same key for 5 times to create duplicate entries.
    for (var i = 0; i < 5; i++) {
      await atClientManager.atClient.put(atKey, value);
      await Future.delayed(Duration(milliseconds: 2));
    }
    var isSyncInProgress = true;
    // Lets the duplicate entries sync to the cloud secondary.
    // Client side commit log compaction removes the duplicate entries that
    // are synced to the cloud secondary.
    atClientManager.atClient.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      print('Sync in progress...');
      await Future.delayed(Duration(milliseconds: 500));
    }

    var atCommitLog =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(secondAtSign);
    var atCompactionStats =
        await AtCompactionService.getInstance().executeCompaction(atCommitLog!);
    expect(
        atCompactionStats.preCompactionEntriesCount >
            atCompactionStats.postCompactionEntriesCount,
        true);
  });
}
