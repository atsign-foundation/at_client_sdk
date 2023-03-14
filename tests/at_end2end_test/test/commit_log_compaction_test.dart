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

  try {
    test('A test to verify commit log compaction job state on switch atSign event', () async {
      var atClientManager = AtClientManager.getInstance();

      // SetCurrentAtSign to firstAtSign. First AtSign's compaction job should be running.
      await atClientManager
          .setCurrentAtSign(firstAtSign, namespace, TestPreferences.getInstance().getPreference(firstAtSign));
      var firstAtClient = atClientManager.atClient as AtClientImpl;
      expect(firstAtClient.atClientCommitLogCompaction?.isCompactionJobRunning(), true);

      // Switch to second AtSign. First AtSign's compaction job should not be running (actually, scheduled)
      // Second AtSign's compaction job should be running.
      await atClientManager
          .setCurrentAtSign(secondAtSign, namespace, TestPreferences.getInstance().getPreference(secondAtSign));
      var secondAtClient = atClientManager.atClient as AtClientImpl;
      expect(firstAtClient.atClientCommitLogCompaction?.isCompactionJobRunning(), false);
      expect(secondAtClient.atClientCommitLogCompaction?.isCompactionJobRunning(), true);

      // Switch back to firstΩ AtSign. Second AtSign's compaction job should not be running (actually, scheduled)
      // First AtSign's compaction job should be running.
      await atClientManager
          .setCurrentAtSign(firstAtSign, namespace, TestPreferences.getInstance().getPreference(firstAtSign));
      firstAtClient = atClientManager.atClient as AtClientImpl;
      expect(firstAtClient.atClientCommitLogCompaction?.isCompactionJobRunning(), true);
      expect(secondAtClient.atClientCommitLogCompaction?.isCompactionJobRunning(), false);
    }, timeout: Timeout(Duration(minutes: 5)));
  } catch (e, s) {
    print(s);
  }
}
