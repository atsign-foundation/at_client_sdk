import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:test/test.dart';
import 'package:at_client/src/compaction/at_commit_log_compaction.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_client/src/preference/at_client_config.dart';

late String firstAtSign;
late String secondAtSign;

late AtClientManager firstAtClientManager;
late AtClientManager secondAtClientManager;

late AtClient firstAtSignAtClient;
late AtClient secondAtSignAtClient;

late AtCommitLog firstAtSignAtCommitLog;
late AtCommitLog secondAtSignAtCommitLog;

final namespace = 'wavi';
late AtServiceFactory atServiceFactory;
late AtClientConfig atClientConfig;

/// The purpose of this test case to verify the commit log compaction job on the first AtSign stops
/// on the switch atSign event and commit log compaction job starts on the second AtSign.

// The setup method contains
// 1. Overriding of AtClientConfig.commitLogCompactionTimeIntervalInMins.
//    Setting the the time interval to 1 minute.
// 2. The initialization of the first atSign's
// AtClientManager, AtClient, AtCommitLog and setting up encryption of keys and
// starting the compaction job on firstAtSign.
// 3. The initialization of the second atSign's AtCommitLog.
Future<void> setUpMethod() async {
  firstAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  secondAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
  // Override the "commitLogCompactionTimeIntervalInMins" to 1 minute
  atClientConfig = AtClientConfig.getInstance()
    ..commitLogCompactionTimeIntervalInMins = 1;
  // Initialize the commit log
  firstAtSignAtCommitLog = (await AtCommitLogManagerImpl.getInstance()
      .getCommitLog(
          firstAtSign,
          enableCommitId: false,
          commitLogPath: TestPreferences.getInstance()
              .getPreference(firstAtSign)
              .commitLogPath))!;
  secondAtSignAtCommitLog = (await AtCommitLogManagerImpl.getInstance()
      .getCommitLog(secondAtSign,
          enableCommitId: false,
          commitLogPath: TestPreferences.getInstance()
              .getPreference(secondAtSign)
              .commitLogPath))!;
  // Get the secondaryPersistentStoreFactory Instance
  var secondaryPersistentStoreFactory =
      SecondaryPersistenceStoreFactory.getInstance()
          .getSecondaryPersistenceStore(firstAtSign);
  // Create the AtCompactionJob instance.
  var atCompactionJob =
      AtCompactionJob(firstAtSignAtCommitLog, secondaryPersistentStoreFactory!);
  var atClientCommitLogCompaction =
      AtClientCommitLogCompaction.create(firstAtSign, atCompactionJob);
  // Create AtClientImpl instance and set the atClientCommitLogCompaction
  // instance and AtClientConfig instance
  firstAtSignAtClient = await AtClientImpl.create(firstAtSign, namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
      atClientCommitLogCompaction: atClientCommitLogCompaction,
      atClientConfig: atClientConfig);

  atServiceFactory = AtServiceFactory()..atClient = firstAtSignAtClient;
  await TestSuiteInitializer.getInstance().testInitializer(
      firstAtSign, namespace,
      atServiceFactory: atServiceFactory);
  firstAtClientManager = await AtClientManager.getInstance().setCurrentAtSign(
      firstAtSign,
      namespace,
      TestPreferences.getInstance().getPreference(firstAtSign),
      atServiceFactory: atServiceFactory);
  firstAtClientManager.atClient.syncService.sync();
}

void main() {
  setUp(() async => await setUpMethod());

  test('A test to verify commit log compaction on switch atSign event',
      () async {
    // Insert 2 keys into the first AtSign to create duplicate entries
    var firstAtSignAtKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(firstAtSign))
        .build();
    var value = '91878723456';
    // Insert the key to create duplicate entries on first AtSign
    await firstAtSignAtClient.put(firstAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await firstAtSignAtClient.put(firstAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    // Hold the commit log entries count on firstAtSign before switch atSign
    var firstAtSignEntriesCountBeforeSwitchAtSign =
        firstAtSignAtCommitLog.entriesCount();
    print(
        'first atSign commit log entries count before switch atSign: $firstAtSignEntriesCountBeforeSwitchAtSign');

    // Create the AtCompactionJob instance for the second atSign.
    var secondaryPersistentStoreFactory =
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(secondAtSign);
    var atCompactionJob = AtCompactionJob(
        secondAtSignAtCommitLog, secondaryPersistentStoreFactory!);
    var atClientCommitLogCompaction =
        AtClientCommitLogCompaction.create(secondAtSign, atCompactionJob);
    // Initialize AtClient for second AtSign
    secondAtSignAtClient = await AtClientImpl.create(secondAtSign, namespace,
        TestPreferences.getInstance().getPreference(secondAtSign),
        atClientCommitLogCompaction: atClientCommitLogCompaction,
        atClientConfig: atClientConfig);
    atServiceFactory = AtServiceFactory()..atClient = secondAtSignAtClient;
    // Initialize AtClientManager for second AtSign
    secondAtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(secondAtSign, namespace,
            TestPreferences.getInstance().getPreference(firstAtSign),
            atServiceFactory: atServiceFactory);
    secondAtClientManager.atClient.syncService.sync();

    // Insert 4 keys into the second AtSign to create duplicate entries
    var secondAtSignAtKey = (AtKey.self('phone', namespace: namespace)
          ..sharedBy(secondAtSign))
        .build();
    await secondAtSignAtClient.put(secondAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await secondAtSignAtClient.put(secondAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await secondAtSignAtClient.put(secondAtSignAtKey, value);
    await Future.delayed(Duration(milliseconds: 2));
    await secondAtSignAtClient.put(secondAtSignAtKey, value);

    // Assert the compaction job changes on the second atSign
    // The entries after compaction should be less than the entries before compaction
    var commitLogEntriesCountBeforeCompaction =
        secondAtSignAtCommitLog.entriesCount();
    print(
        'Second atSign commit log entries count before compaction: $commitLogEntriesCountBeforeCompaction');
    // Wait for 1 minute + 12 seconds (random delay added in compaction job)for the compaction job
    // to complete.
    await Future.delayed(Duration(seconds: 72));
    var commitLogEntriesCountAfterCompaction =
        secondAtSignAtCommitLog.entriesCount();
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
        firstAtSignAtCommitLog.entriesCount();
    print(
        'first atSign commit log entries count after switch atSign: $firstAtSignEntriesCountAfterSwitchAtSign');
    expect(
        firstAtSignEntriesCountBeforeSwitchAtSign >=
            firstAtSignEntriesCountAfterSwitchAtSign,
        true);
  }, timeout: Timeout(Duration(minutes: 2)));
}
