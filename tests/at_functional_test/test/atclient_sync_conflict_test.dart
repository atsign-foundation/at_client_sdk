import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/at_keys_intialializer.dart';
import 'package:at_functional_test/src/sync_progress_listener.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'test_utils.dart';

void main() async {
  late AtClientManager atClientManager;
  late MySyncProgressListener mySyncProgressListener;
  final atSign = '@alice🛠';
  String namespace = 'wavi';

  setUpAll(() async {
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', TestUtils.getPreference(atSign));
    // To setup encryption keys
    await AtEncryptionKeysLoader.getInstance()
        .setEncryptionKeys(atClientManager.atClient, atSign);
  });

  // The SyncProgressListener is removed and stream is closed at the end of each test.
  // So, create an instance of SyncProgressListener at the start of each test
  setUp(() async {
    mySyncProgressListener = MySyncProgressListener();
    atClientManager.atClient.syncService
        .addProgressListener(mySyncProgressListener);
  });

  test('notify updating of a key to sharedWith atSign - using await', () async {
    // Insert 5 keys into the keystore for uncommitted entries
    // among which, one is a conflict key - phone_0.wavi is a conflict key.
    for (var i = 0; i < 5; i++) {
      var phoneKey = AtKey()..key = 'phone_$i';
      var value = '$i';
      await atClientManager.atClient.put(phoneKey, value);
    }
    // Update the key directly to remote secondary for having
    // the conflict key during sync
    final updateVerbBuilder = UpdateVerbBuilder()
      ..sharedBy = atSign
      ..atKey = 'phone_0.wavi'
      ..value = 'sMBnYFctMOg+lqX67ah9UA==' //encrypted value of 4
      ..isEncrypted = true;
    await atClientManager.atClient
        .getRemoteSecondary()!
        .executeVerb(updateVerbBuilder);

    await FunctionalTestSyncService.getInstance()
        .syncData(atClientManager.atClient.syncService);

    mySyncProgressListener.streamController.stream
        .listen(expectAsync1((SyncProgress syncProgress) {
      expect(syncProgress.syncStatus, SyncStatus.success);
      expect(syncProgress.keyInfoList, isNotEmpty);
      for (var keyInfo in syncProgress.keyInfoList!) {
        if (keyInfo.key == 'phone_0.wavi@alice🛠' &&
            keyInfo.syncDirection == SyncDirection.remoteToLocal) {
          expect(keyInfo.conflictInfo != null, true);
          expect(keyInfo.conflictInfo?.remoteValue, '4');
          expect(keyInfo.conflictInfo?.localValue, '0');
        }
      }
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
    }));
  });

  /// The purpose of this test verify the following:
  /// 1. Updating a key with ttl 10ms to the cloud (Key becomes null after 10s in the server)
  /// 2. Updating the same key in the client with a non null value
  /// 3. Verifying that sync conflict is populated with no exception thrown
  test(
      'A test to verify sync conflict info when a key is expired and server value is null',
      () async {
    // Insert a key into local secondary for an uncommitted entry
    var testKey =
        AtKey.public('test', namespace: namespace, sharedBy: atSign).build();
    await atClientManager.atClient.put(testKey, '123');
    // Insert the same key directly into the remote secondary for having the
    // conflicting key during sync
    final remoteSecondary = atClientManager.atClient.getRemoteSecondary()!;
    final updateVerbBuilder = UpdateVerbBuilder()
      ..sharedBy = atSign
      ..atKey = 'test.$namespace'
      ..ttl = 2
      ..isPublic = true
      ..value = 'randomvalue';
    await remoteSecondary.executeVerb(updateVerbBuilder);
    // Wait for 12 milliseconds to the key to expire
    await Future.delayed(Duration(seconds: 1));

    await FunctionalTestSyncService.getInstance()
        .syncData(atClientManager.atClient.syncService);

    mySyncProgressListener.streamController.stream
        .listen(expectAsync1((SyncProgress syncProgress) {
      print(syncProgress);
      expect(syncProgress.syncStatus, SyncStatus.success);
      expect(syncProgress.keyInfoList, isNotEmpty);
      for (var keyInfo in syncProgress.keyInfoList!) {
        if (keyInfo.key == 'test.$namespace$atSign' &&
            keyInfo.syncDirection == SyncDirection.remoteToLocal) {
          expect(keyInfo.conflictInfo != null, true);
        }
      }
      expect(syncProgress.localCommitId,
          greaterThan(syncProgress.localCommitIdBeforeSync!));
    }));
  });

  tearDown(() async {
    atClientManager.atClient.syncService.removeAllProgressListeners();
    await mySyncProgressListener.streamController.close();
  });
}
