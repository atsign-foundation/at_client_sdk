import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_client/src/preference/at_client_config.dart';

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
  // Override the "commitLogCompactionTimeIntervalInMins" to 1 minute
  AtClientConfig.getInstance().commitLogCompactionTimeIntervalInMins = 1;
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

    var firstAtSignAtKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(firstAtSign))
        .build();
    var value = '91878723456';
    // Insert the key to create duplicate entries on first AtSign
    await firstAtClientManager.atClient.put(firstAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await firstAtClientManager.atClient.put(firstAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    // Hold the commit log entries count on firstAtSign before switch atSign
    firstAtSignAtCommitLog =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(firstAtSign);
    var firstAtSignEntriesCountBeforeSwitchAtSign =
        firstAtSignAtCommitLog!.entriesCount();
    print(
        'first atSign commit log entries count before switch atSign: $firstAtSignEntriesCountBeforeSwitchAtSign');

    // Initialize AtClientManager for second AtSign
    secondAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(secondAtSign, namespace,
            TestPreferences.getInstance().getPreference(secondAtSign));
    secondAtClientManager.atClient.syncService.sync();

    // Insert 4 keys into the second AtSign to create duplicate entries
    var secondAtSignAtKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(secondAtSign))
        .build();
    await secondAtClientManager.atClient.put(secondAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await secondAtClientManager.atClient.put(secondAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await secondAtClientManager.atClient.put(secondAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await secondAtClientManager.atClient.put(secondAtSignAtKey, value);

    // Assert the compaction job changes on the second atSign
    // The entries after compaction should be less than the entries before compaction
    secondAtSignAtCommitLog =
        await AtCommitLogManagerImpl.getInstance().getCommitLog(secondAtSign);
    var commitLogEntriesCountBeforeCompaction =
        secondAtSignAtCommitLog!.entriesCount();
    print(
        'Second atSign commit log entries count before compaction: $commitLogEntriesCountBeforeCompaction');
    // Wait for 1 minute + 12 seconds (random delay added in compaction job)for the compaction job
    // to complete.
    await Future.delayed(Duration(seconds: 72));
    var commitLogEntriesCountAfterCompaction =
        secondAtSignAtCommitLog!.entriesCount();
    print(
        'Second atSign commit log entries count after compaction: $commitLogEntriesCountAfterCompaction');
    expect(
        commitLogEntriesCountAfterCompaction <
            commitLogEntriesCountBeforeCompaction,
        true);

    // Assert the compaction job did not run on first atSign
    // The commit log entries on the first atSign before switch atSign should be
    // greater than or equal to commit log entries after switch atSign.
    var firstAtSignEntriesCountAfterSwitchAtSign =
        firstAtSignAtCommitLog!.entriesCount();
    print(
        'first atSign commit log entries count after switch atSign: $firstAtSignEntriesCountAfterSwitchAtSign');
    expect(
        firstAtSignEntriesCountBeforeSwitchAtSign >=
            firstAtSignEntriesCountAfterSwitchAtSign,
        true);
  }, timeout: Timeout(Duration(minutes: 3)));
}
