import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync/sync_request.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/src/keystore/hive_keystore.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {
  var remoteKeyStore = {};

  @override
  Future<String?> executeCommand(String atCommand, {bool auth = false}) async {
    return 'success';
  }
}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() {
    return '@bob';
  }

  @override
  AtClientPreference? getPreferences() {
    return AtClientPreference();
  }
}

class MockNotificationServiceImpl extends Mock
    implements NotificationServiceImpl {
  @override
  Stream<at_notification.AtNotification> subscribe(
      {String? regex, bool shouldDecrypt = false}) {
    return StreamController<at_notification.AtNotification>().stream;
  }
}

class MockNetworkUtil extends Mock implements NetworkUtil {
  @override
  Future<bool> isNetworkAvailable() {
    return Future.value(true);
  }
}

///Notes:
/// Description of terminology used in the test cases:
///
/// 1. Create = A key does not exist previously and it is being newly created
/// 2. Update = A key exists previously
/// 3. Recreate = A key that exists previously got deleted and it is being created again

void main() {
  String atsign = '@bob';
  // (Client) How items are added to the 'uncommitted' queue on the client side (upon data store operations)
  // (Client) How the client processes that uncommitted queue (while sending updates to server) - e.g. how is the queue ordered, how is it de-duped, etc
  // (Client) How the client processes updates from the server - can the client reject? under what conditions? what happens upon a rejection?
  // The 7th contract is the contract for precisely how the client and server exchange information. Currently this is implemented using the batch verb and has state like 'syncInProgress' and 'isInSync'. (Aside: Fsync will implement this contract in a streaming fashion bidirectionally.)

  group(
      'Tests to validate how items are added to the uncommitted queue on the client side (upon data store operations)',
      () {
    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    /// Operation:
    /// Put a public key

    /// Assertions:
    /// 1. Key store should have the public key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be set to 0
    /// 4. CommitLog should have an entry for the new public key with commitOp.Update
    /// and commitId is null
    test('Verify uncommitted queue on creation of a public key', () async {
      //------------Setup---------------------------------
      await TestResources.setupLocalStorage(atsign, enableCommitId: false);
      HiveKeystore? keystore = TestResources.getHiveKeyStore(atsign);
      var atData = AtData();
      atData.data = 'Hyderabad';
      //------------------Operation-------------
      //  creating a key in the keystore
      String atKey = (AtKey.public('city', namespace: 'wavi', sharedBy: atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      //------------------Assertions-------------
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      expect(keyStoreGetResult.metaData!.version, 0);;
      int? seqNum = TestResources.commitLog!.lastCommittedSequenceNumber();
      var syncedENtry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getChangesSinceLastCommit(seqNum, 'wavi', atSign: atsign);
      print(syncedENtry);
      expect(syncedENtry[0].operation, CommitOp.UPDATE);
      expect(syncedENtry[0].commitId, null);
    });
  });
}

class TestResources {
  static AtCommitLog? commitLog;
  static SecondaryPersistenceStore? secondaryPersistenceStore;
  static var storageDir = '${Directory.current.path}/test/hive';

  static Future<void> setupLocalStorage(String atsign,
      {bool enableCommitId = false}) async {
    commitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(atsign,
        commitLogPath: storageDir, enableCommitId: enableCommitId);
    var secondaryPersistenceStore =
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(atsign)!;
    await secondaryPersistenceStore
        .getHivePersistenceManager()!
        .init(storageDir);
    secondaryPersistenceStore.getSecondaryKeyStore()!.commitLog = commitLog;
  }

  static Future<void> tearDownLocalStorage() async {
    try {
      var isExists = await Directory(storageDir).exists();
      if (isExists) {
        Directory(storageDir).deleteSync(recursive: true);
      }
    } catch (e, st) {
      print('sync_test.dart: exception / error in tearDown: $e, $st');
    }
  }

  static HiveKeystore? getHiveKeyStore(String atsign) {
    return SecondaryPersistenceStoreFactory.getInstance()
        .getSecondaryPersistenceStore(atsign)
        ?.getSecondaryKeyStore();
  }
}
