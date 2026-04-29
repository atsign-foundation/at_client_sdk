import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_progress_listener.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() async {
  late AtClientManager atClientManager;
  late String atSign;
  String namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atClientManager = await TestUtils.initAtClient(atSign, namespace);
  });

  setUp(() async {
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: atClientManager.atClient.syncService);
  });

  tearDown(() async {
    atClientManager.atClient.syncService.removeAllProgressListeners();
  });

  test('notify updating of a key to sharedWith atSign - using await', () async {
    // Suspend sync while we set up the conflict scenario. With the on-
    // demand sync trigger model, every local put would otherwise
    // trigger an immediate microtask-driven sync run, pushing each
    // phone_X to the server as it lands and eliminating the conflict
    // we're trying to create on phone_0.
    await (atClientManager.atClient.syncService as SyncServiceImpl).stop();

    // Insert 5 keys into the keystore for uncommitted entries
    // among which, one is a conflict key - phone_0.wavi is a conflict key.
    for (var i = 0; i < 5; i++) {
      var phoneKey = AtKey.fromString('phone_$i.$namespace$atSign');
      var value = '$i';
      await atClientManager.atClient.put(phoneKey, value);
    }

    // Update the key directly to remote secondary for having
    // the conflict key during sync
    AtKey remoteKey = AtKey.fromString('phone_0.$namespace$atSign');
    await atClientManager.atClient.put(remoteKey, 'Things have changed',
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true);

    // Restart sync and add the listener AFTER the conflict has been
    // staged. stop() removed all listeners, so pl is added fresh.
    await (atClientManager.atClient.syncService as SyncServiceImpl).start();
    MySyncProgressListener pl = MySyncProgressListener(true);
    atClientManager.atClient.syncService.addProgressListener(pl);

    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: atClientManager.atClient.syncService);

    Completer<SyncProgress> progress = Completer();
    pl.streamController.stream.listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;
    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    bool foundKeyInfo = false;
    for (var keyInfo in syncProgress.keyInfoList!) {
      if (keyInfo.key == 'phone_0.wavi@alice🛠' &&
          keyInfo.syncDirection == SyncDirection.remoteToLocal) {
        foundKeyInfo = true;
        expect(keyInfo.conflictInfo, isNotNull);
        expect(keyInfo.conflictInfo?.remoteValue, 'Things have changed');
        expect(keyInfo.conflictInfo?.localValue, '0');
      }
    }
    expect(foundKeyInfo, true);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));

    await Future.delayed(Duration(milliseconds: 10));
  });

  /// The purpose of this test verify the following:
  /// 1. Updating a key with ttl 10ms to the cloud (Key becomes null after 10s in the server)
  /// 2. Updating the same key in the client with a non null value
  /// 3. Verifying that sync conflict is populated with no exception thrown
  test(
      'A test to verify sync conflict info when a key is expired and server value is null',
      () async {
    // Same pattern as the first conflict test: stop sync while we
    // stage the conflict so the on-demand trigger doesn't push the
    // local entry before the remote-direct put creates the conflict.
    await (atClientManager.atClient.syncService as SyncServiceImpl).stop();

    // Insert a key into local secondary for an uncommitted entry
    var testKey =
        AtKey.public('test', namespace: namespace, sharedBy: atSign).build();
    await atClientManager.atClient.put(testKey, '123');
    // Insert the same key directly into the remote secondary for having the
    // conflicting key during sync
    final remoteSecondary = atClientManager.atClient.getRemoteSecondary()!;
    final updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'test.$namespace'
        ..sharedBy = atSign
        ..metadata = (Metadata()
          ..ttl = 2 // expires in two milliseconds
          ..isPublic = true))
      ..value = 'randomvalue';
    await remoteSecondary.executeVerb(updateVerbBuilder);
    // Wait for a few milliseconds to the key to expire
    await Future.delayed(Duration(milliseconds: 10));

    await (atClientManager.atClient.syncService as SyncServiceImpl).start();
    MySyncProgressListener mySyncProgressListener =
        MySyncProgressListener(true);
    atClientManager.atClient.syncService
        .addProgressListener(mySyncProgressListener);

    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: atClientManager.atClient.syncService);

    Completer<SyncProgress> progress = Completer();
    mySyncProgressListener.streamController.stream
        .listen((SyncProgress syncProgress) {
      if (!progress.isCompleted) {
        progress.complete(syncProgress);
      }
    });
    SyncProgress syncProgress = await progress.future;
    expect(syncProgress.syncStatus, SyncStatus.success);
    expect(syncProgress.keyInfoList, isNotEmpty);
    bool foundKeyInfo = false;
    for (var keyInfo in syncProgress.keyInfoList!) {
      if (keyInfo.key.contains('test.$namespace$atSign') &&
          keyInfo.syncDirection == SyncDirection.remoteToLocal) {
        foundKeyInfo = true;
        expect(keyInfo.conflictInfo != null, true);
      }
    }
    expect(foundKeyInfo, true);
    expect(syncProgress.localCommitId,
        greaterThan(syncProgress.localCommitIdBeforeSync!));
  });
}
