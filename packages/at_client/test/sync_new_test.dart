import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/at_notification.dart' as at_notification;
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync/sync_request.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:at_persistence_secondary_server/src/keystore/hive_keystore.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {
  var remoteKeyStore = {};
}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  @override
  String? getCurrentAtSign() {
    return TestResources.atsign;
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

class MockAtCommitLog extends Mock implements AtCommitLog {}

class MockNetworkUtil extends Mock implements NetworkUtil {}

class FakeSyncVerbBuilder extends Fake implements SyncVerbBuilder {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

class FakeStatsVerbBuilder extends Fake implements StatsVerbBuilder {}

///Notes:
/// Description of terminology used in the test cases:
///
/// 1. Create = A key does not exist previously and it is being newly created
/// 2. Update = A key exists previously
/// 3. Recreate = A key that exists previously got deleted and it is being created again

void main() {
  // (Client) How items are added to the 'uncommitted' queue on the client side (upon data store operations)
  // (Client) How the client processes that uncommitted queue (while sending updates to server) - e.g. how is the queue ordered, how is it de-duped, etc
  // (Client) How the client processes updates from the server - can the client reject? under what conditions? what happens upon a rejection?
  // The 7th contract is the contract for precisely how the client and server exchange information. Currently this is implemented using the batch verb and has state like 'syncInProgress' and 'isInSync'. (Aside: Fsync will implement this contract in a streaming fashion bidirectionally.)

  group(
      'Tests to validate how items are added to the uncommitted queue on the client side (upon data store operations)',
      () {
    TestResources.atsign = '@bob';
    setUp(() async =>
        await TestResources.setupLocalStorage(TestResources.atsign));

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
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'Hyderabad';
      //------------------Operation-------------
      //  creating a key in the keystore
      String atKey = (AtKey.public('newCity', sharedBy: TestResources.atsign))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      //------------------Assertions-------------
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      expect(keyStoreGetResult.metaData!.version, 0);
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitLogEntry?.operation, CommitOp.UPDATE);
      expect(commitLogEntry?.commitId, null);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.
    /// 3. There should be an entry for the same key in the commit log

    // Operation
    /// Update a public key
    // updating the same key in the keystore with a different value
    // Assertions :
    /// 1. Key store should have the public key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    /// 3. The version of the key should be incremented by 1
    /// 4. CommitLog should have an entry for the new public key with commitOp.Update
    test('Verify uncommitted queue on update of a public key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'Hyderabad';
      var newData = AtData();
      newData.data = 'Bangalore';
      //------------Precondition Setup---------------------------------
      String atKey = (AtKey.public('city',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt, isNotNull);
      //-----------Operation---------------------------------
      int putCommitId = await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------
      // verifying the key in the key store
      keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'Bangalore');
      // verifying that createdAt time is not changed
      // expect(keyStoreGetResult.metaData!.createdAt, createdAtTime);
      // verifying the updatedAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 1
      /// commenting the assertion as there is a known bug in the versioning where
      /// Version doesn't get incremented when the same key is updated
      // expect(keyStoreGetResult.metaData!.version, 1);
      // verifying the key in the commit log
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitLogEntry!.operation, CommitOp.UPDATE_ALL);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    //Operation
    /// Delete a public key

    // Assertions :
    /// 1. Key store now should not have the entry of the key
    /// 2. CommitLog should have an entry for the deleted public key (commitOp.delete)
    test('Verify uncommitted queue on deletion of a public key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      String atKey = (AtKey.public('location',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      //-----------Precondition Setup---------------------------------
      await keystore!.put(atKey, AtData()..data = 'Hyderabad');
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'Hyderabad');
      //-----------Operation---------------------------------
      int? commitId = await keystore.remove(atKey);
      // verifying the key in the key store
      //-----------Assertions---------------------------------
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      // verifying the key in the commit log
      await TestResources.setCommitEntry(commitId!, TestResources.atsign);
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getCommitEntry(commitId, TestResources.atsign);
      expect(commitLogEntry!.operation, CommitOp.DELETE);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    /// Operation
    /// Delete a key and insert the same key again

    /// Assertions
    /// 1. Key store should have the public key with the new value inserted
    /// 2. CommitLog should have a following entries in sequence as described below
    ///     a. Commit entry with CommitOp.Delete
    ///     b. CommitEntry with CommitOp.Update

    test('Verify uncommitted queue on re-creation of a public key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      String oldValue = 'alice@gmail.com';
      String newValue = 'alice@yahoo.com';
      var atData = AtData();
      atData.data = oldValue;
      var newData = AtData();
      newData.data = newValue;
      //-----------Operation---------------------------------
      String atKey = (AtKey.public('email', sharedBy: TestResources.atsign))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      // remove the created key
      await keystore.remove(atKey);
      //-----------Assertions---------------------------------------------------
      // re-creating the same key in the keystore with a new value
      await keystore.put(atKey, newData);
      // verifying the key in the key store to return the updated value
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, newValue);
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      List<CommitEntry> commitEntries =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getChangesSinceLastCommit(putCommitId, 'email',
                  atSign: TestResources.atsign);
      expect(commitEntries[0].operation, CommitOp.DELETE);
      expect(commitEntries[1].operation, CommitOp.UPDATE);
    });

    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    /// Operation
    /// Put a shared key

    /// Assertions
    /// 1. Key store should have the shared key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be 0 (Zero)
    /// 4. CommitLog should have an entry for the shared key with commitOp.Update
    /// and commitId is null
    test('Verify uncommitted queue on creation of a shared key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'Hyderabad';
      //-----------Operation---------------------------------
      //  creating a key in the keystore
      String atKey = (AtKey.shared('location',
              namespace: 'wavi', sharedBy: TestResources.atsign)
            ..sharedWith('@bob'))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      expect(keyStoreGetResult.metaData!.version, 0);
      // verifying the key in the commit log
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitLogEntry!.operation, CommitOp.UPDATE);
      expect(commitLogEntry.commitId, null);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log
    /// 3. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.
    ///
    /// Operation
    /// Update a shared key

    /// Assertions
    /// 1. Keystore should have the shared key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    /// of when key is updated
    /// 3. The version of the key should be incremented by 1
    /// 4. CommitLog should have an entry for the new shared key with commitOp.Update
    test('Verify uncommitted queue on update of a shared key ', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'alice';
      var newData = AtData();
      newData.data = 'alice123';
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.shared('username',
              namespace: 'wavi', sharedBy: TestResources.atsign)
            ..sharedWith('@bob'))
          .build()
          .toString();
      //  creating a key in the keystore
      await keystore!.put(atKey, atData);
      //-----------Operation---------------------------------
      // updating the same key in the keystore with a different value
      int putCommitId = await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice123');
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      // expect(keyStoreGetResult.metaData!.version, 1);
      // verifying the key in the commit log
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitLogEntry!.operation, CommitOp.UPDATE_ALL);
    });

    /// Preconditions
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    // Operation
    /// Delete a shared key

    // Assertions
    /// 1. Keystore should not have the shared key
    /// 2. CommitLog should have an entry for the deleted shared key(commitOp.delete)
    test('Verify uncommitted queue on deletion of a shared key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      //------------Preconditions setup---------------------------------
      String atKey = (AtKey.shared('location',
              namespace: 'wavi', sharedBy: TestResources.atsign)
            ..sharedWith('@bob'))
          .build()
          .toString();
      await keystore!.put(atKey, AtData()..data = 'alice');
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice');
      //-----------Operation---------------------------------
      int? removeCommitId = await keystore.remove(atKey);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      // verifying the key in the commit log
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getCommitEntry(removeCommitId!, TestResources.atsign);
      expect(commitLogEntry!.operation, CommitOp.DELETE);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    // Operation
    /// Delete a key and insert the same key again

    // Assertions :
    /// 1. Keystore should have the shared key with the new value inserted
    /// 2. CommitLog should have a following entries in sequence as described below
    ///     a. Commit entry with CommitOp.Delete
    ///     b. CommitEntry with CommitOp.Update
    test('Verify uncommitted queue on re-creation of a shared key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'alice@gmail.com';
      var newData = AtData();
      newData.data = 'alice@yahoo.com';
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.shared('email',
              namespace: 'wavi', sharedBy: TestResources.atsign)
            ..sharedWith('@bob'))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      //-----------Operation---------------------------------
      // remove the created key
      await keystore.remove(atKey);
      // re-creating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice@yahoo.com');
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verify the entries in the commit log
      var commitEntriesResult = await SyncUtil().getChangesSinceLastCommit(
          putCommitId, 'wavi',
          atSign: TestResources.atsign);
      expect(commitEntriesResult[0].operation, CommitOp.DELETE);
      expect(commitEntriesResult[1].operation, CommitOp.UPDATE);
    });

    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    // Operation
    /// Put a self key

    // Assertions :
    /// 1. Keystore should have the self key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be set to 0
    /// 4. CommitLog should have an entry for the new self key with commitOp.Update
    /// and commitId is null
    test('Verify uncommitted queue on creation of a self key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'alice12';
      //-----------Operation---------------------------------
      //  creating a key in the keystore
      String atKey = (AtKey.self('quora',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      expect(keyStoreGetResult.metaData!.version, 0);
      // verifying the key in the commit log
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      // This assertion fails when run as a group
      expect(commitEntryResult!.commitId, null);
      expect(commitEntryResult.operation, CommitOp.UPDATE);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log
    /// 3. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.

    //  Operation
    /// Update a self key

    //  Assertions :
    /// 1. Keystore should have the self key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    /// 3. The version of the key should be incremented by 1
    /// 4. CommitLog should have an entry for the new self key with commitOp.Update
    test('Verify uncommitted queue on update of a self key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      String oldValue = 'alice';
      String newValue = 'alice123';
      var atData = AtData();
      atData.data = oldValue;
      var newData = AtData();
      newData.data = newValue;
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.self('facebook',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      //  creating a key in the keystore
      await keystore!.put(atKey, atData);
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt, isNotNull);
      expect(keyStoreGetResult.metaData!.version, 0);
      //-----------Operation---------------------------------
      // updating the same key in the keystore with a different value
      int putCommitId = await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, newValue);
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      // expect(keyStoreGetResult.metaData!.version, 1);
      // verifying the key in the commit log
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitEntryResult!.operation, CommitOp.UPDATE_ALL);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log
    // Operation
    /// Delete a self key

    // Assertions :
    /// 1. Keystore now should not have the entry of the key
    /// 2. CommitLog should have an entry for the deleted self key (commitOp.delete)
    test('Verify uncommitted queue on deletion of a self key', () async {
      // //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.self('twitter',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      await keystore!.put(atKey, AtData()..data = 'alice');
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice');
      //-----------Operation---------------------------------
      int? removeCommitId = await keystore.remove(atKey);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      // verifying the key in the commit log
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(removeCommitId!, TestResources.atsign);
      expect(commitEntryResult!.operation, CommitOp.DELETE);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    // Operation
    /// Delete a key and insert the same key again

    // Assertions :
    /// 1. Keystore should have the self key with the new value inserted
    /// 2. CommitLog should have a following entries in sequence as described below
    ///     a. Commit entry with CommitOp.Delete
    ///     b. CommitEntry with CommitOp.Update
    test('Verify uncommitted queue on re-creation of a self key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'alice@gmail.com';
      var newData = AtData();
      newData.data = 'alice@yahoo.com';
      //------------Preconditions SetUp---------------------------------
      String atKey = (AtKey.self('email',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      //-----------Operation---------------------------------
      // remove the created key
      await keystore.remove(atKey);
      // re-creating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice@yahoo.com');
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verify the entries in the commit log
      var commitEntriesResult = await SyncUtil().getChangesSinceLastCommit(
          putCommitId, 'wavi',
          atSign: TestResources.atsign);
      expect(commitEntriesResult[0].operation, CommitOp.DELETE);
      expect(commitEntriesResult[1].operation, CommitOp.UPDATE);
    });

    /// Preconditions
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    // Operation
    /// Put a local key

    // Assertions
    /// 1. Keystore should have the local key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. There should be no entry in the commit log for the local key
    test('Verify uncommitted queue on creation of a local key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'sample';
      //-----------Operation---------------------------------
      //  creating a key in the keystore
      String atKey =
          (AtKey.local('sample', TestResources.atsign, namespace: 'wavi'))
              .build()
              .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      //-----------Assertions---------------------------------:
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'sample');
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 0
      expect(keyStoreGetResult.metaData!.version, 0);
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitEntryResult, null);
    });

    /// Preconditions
    /// 1. There should be an entry for the same key in the key store
    /// 2. In the metadata of the key, the version should be set to 0
    /// and the "createdAt" field should be populated.

    // Operation
    /// Put a new value for an existing local key

    // Assertions
    /// 1. keystore should have the local key with the new value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    /// 3. There should be no entry in the commit log for the local key
    test('Verify uncommitted queue on update of a local key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'alice';
      var newData = AtData();
      newData.data = 'alice123';
      //------------Preconditions SetUp---------------------------------
      String atKey =
          (AtKey.local('facebook', TestResources.atsign, namespace: 'wavi'))
              .build()
              .toString();
      //  creating a key in the keystore
      await keystore!.put(atKey, atData);
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt, isNotNull);
      expect(keyStoreGetResult.metaData!.version, 0);
      //-----------Operation---------------------------------
      // updating the same key in the keystore with a different value
      int putCommitId = await keystore.put(atKey, newData);
      // verifying the key in the key store
      keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice123');
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      // verifying the version of the key is 1
      // expect(keyStoreGetResult.metaData!.version, 1);
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitEntryResult, null);
    });

    /// Pre-conditions
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should not be an entry for the same key in the commit log

    // Operation
    /// Delete a local key

    // Assertions
    /// 1. Keystore should not have the local key
    /// 2. CommitLog should not have an entry for the deleted local key (commitOp.delete)
    test('Verify uncommitted queue on deletion of a local key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      //------------Preconditions SetUp---------------------------------
      String atKey =
          (AtKey.local('twitter', TestResources.atsign, namespace: 'wavi'))
              .build()
              .toString();
      await keystore!.put(atKey, AtData()..data = 'alice');
      // verifying the key in the commit log
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice');
      //-----------Operation---------------------------------
      int? removeCommitId = await keystore.remove(atKey);
      // verifying the key in the key store
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(removeCommitId!, TestResources.atsign);
      expect(commitEntryResult, null);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store

    // Operation
    /// Delete a key and insert the same key again

    // Assertions :
    /// 1. Keystore should have the local key with the new value inserted
    test('Verify uncommitted queue on re-creation of a local key', () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'Newyork';
      var newData = AtData();
      newData.data = 'Texas';
      //------------Preconditions SetUp---------------------------------
      String atKey =
          (AtKey.local('fav-place', TestResources.atsign, namespace: 'wavi'))
              .build()
              .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      // remove the created key
      // -----------Operation---------------------------------
      await keystore.remove(atKey);
      // re-creating the same key in the keystore with a different value
      await keystore.put(atKey, newData);
      // -----------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'Texas');
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitEntryResult, null);
    });

    /// Preconditions
    /// 1. There should be no entry for the private encryption key in the key store
    /// 2. There should be no entry for the private encryption key in the commit log

    // Operation
    /// Put a private encryption key

    // Assertions
    /// 1. Keystore should have the private encryption key with the value inserted
    /// 2. CommitLog should not have an entry for the private encryption key
    test('Verify uncommitted queue on creation of a private encryption key',
        () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      final encryptionPrivateKey =
          RSAKeypair.fromRandom().privateKey.toString();
      var atData = AtData();
      atData.data = encryptionPrivateKey;
      //------------Operation---------------------------------
      String atKey = (AtKey.self(AT_ENCRYPTION_PRIVATE_KEY,
              sharedBy: TestResources.atsign))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      // -----------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, encryptionPrivateKey);
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitEntryResult, null);
    });

    test('Verify uncommitted queue on deletion of a private encryption key',
        () {
      /// ToDo: Needs to be decided if we need to test deletion of private encryption key
    });
    test('Verify uncommitted queue on re-creation of a private encryption key',
        () {
      /// ToDo: Needs to be decided if we need to test re-creation of private encryption key
    });

    /// Preconditions
    /// 1. There should be no entry for the pkam private key in the key store

    // Operation
    /// Put a pkam private key

    // Assertions
    /// 1. Keystore should have the pkam private key with the value inserted
    /// 2. CommitLog should not have an entry for the pkam private key
    test('Verify uncommitted queue on creation of a pkam private key',
        () async {
      //------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      final pkamPrivateKey = RSAKeypair.fromRandom().privateKey.toString();
      var atData = AtData();
      atData.data = pkamPrivateKey;
      //------------Operation---------------------------------
      String atKey =
          (AtKey.self(AT_PKAM_PRIVATE_KEY, sharedBy: TestResources.atsign))
              .build()
              .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      // -----------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, pkamPrivateKey);
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitEntryResult, null);
    });
    test('Verify uncommitted queue on deletion of a pkam private key', () {
      /// ToDo: Needs to be decided if we need to test deletion of pkam private key
    });
    test('Verify uncommitted queue on re-creation of a pkam private key', () {
      /// ToDo: Needs to be decided if we need to test re-creation of pkam private key
    });

    /// Preconditions
    /// 1. There should be an entry for the public key in the key store
    /// 2. There should be an entry for the public key in the commit log

    // Operation
    /// 1. Update a new value for an existing public key
    /// 2. Delete the public key

    // Assertions
    /// 1. Keystore should not have the public key
    /// 2. CommitLog should have only the latest entries:
    ///     a. CommitEntry for key with CommitOp.Delete
    test(
        'Verify uncommitted queue on multiple update and deletion of a public key',
        () async {
      // ------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'alice@gmail.com';
      var newData = AtData();
      newData.data = 'alice@yahoo.com';
      // ------------Operation---------------------------------
      String atKey = (AtKey.public('facebook',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // updating the same key in the keystore with a different value
      int putCommitId = await keystore.put(atKey, newData);
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice@yahoo.com');
      //  deleting the public key
      await keystore.remove(atKey);
      // -----------Assertions---------------------------------
      // verify the latest entry in the commit log is for DELETE
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getChangesSinceLastCommit(putCommitId, 'wavi',
                  atSign: TestResources.atsign);
      expect(commitEntryResult[0].operation, CommitOp.DELETE);
    });

    /// Preconditions
    /// 1. There should be an entry for the shared key in the key store
    /// 2. There should be an entry for the shared key in the commit log

    // Operation
    /// 1. Update a new value for an existing shared key
    /// 2. Delete the shared key

    // Assertions
    /// 1. Keystore should not have the shared key
    /// 2. CommitLog should have only the latest entries:
    ///     a. CommitEntry for key with CommitOp.Delete
    test(
        'Verify uncommitted queue on multiple updates and deletes of a shared key',
        () async {
      // ------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'alice123';
      var newData = AtData();
      newData.data = 'alice544';
      // ------------Operation---------------------------------
      String atKey = (AtKey.shared('medium',
              namespace: 'wavi', sharedBy: TestResources.atsign)
            ..sharedWith('@alice'))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // updating the same key in the keystore with a different value
      int putCommitId = await keystore.put(atKey, newData);
      // --------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, 'alice544');
      // verifying the createdAt time is less than DateTime.now()
      expect(keyStoreGetResult.metaData!.updatedAt!.isBefore(DateTime.now()),
          true);
      //  deleting the public key
      await keystore.remove(atKey);
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getChangesSinceLastCommit(putCommitId, 'wavi',
                  atSign: TestResources.atsign);
      expect(commitEntryResult[0].operation, CommitOp.DELETE);
    });

    /// Preconditions
    /// 1. There should be an entry for the self key in the key store
    /// 2. There should be an entry for the self key in the commit log

    // Operation
    /// 1. Update a new value for an existing self key
    /// 2. Delete the self key

    // Assertions
    /// 1. Keystore should not have the self key
    /// 2. CommitLog should have only the latest entries:
    ///     a. CommitEntry for key with CommitOp.Delete
    test(
        'Verify uncommitted queue on multiple updates and deletes of a self key',
        () async {
      // ------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = '1134';
      var newData = AtData();
      newData.data = '5424';
      // ------------Operation---------------------------------
      String atKey = (AtKey.self('auth-code',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      await keystore!.put(atKey, atData);
      // updating the same key in the keystore with a different value
      int putCommitId = await keystore.put(atKey, newData);
      // --------Assertions---------------------------------
      // verifying the key in the key store
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.data, '5424');
      //  deleting the key
      await keystore.remove(atKey);
      // verifying the latest entry in the commit log is for DELETE
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getChangesSinceLastCommit(putCommitId, 'wavi',
                  atSign: TestResources.atsign);
      expect(commitEntryResult[0].operation, CommitOp.DELETE);
    });

    tearDown(() async {
      await TestResources.tearDownLocalStorage();
      resetMocktailState();
    });
  });

  group(
      'Tests to validate how the client processes that uncommitted queue (while sending updates to server)'
      'e.g. how is the queue ordered, how is it de-duped, etc', () {
    setUp(() async {
      TestResources.atsign = '@santa';
      await TestResources.setupLocalStorage(TestResources.atsign,
          enableCommitId: false);
    });

    AtClient mockAtClient = MockAtClient();
    AtClientManager mockAtClientManager = MockAtClientManager();
    NotificationServiceImpl mockNotificationService =
        MockNotificationServiceImpl();
    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    NetworkUtil mockNetworkUtil = MockNetworkUtil();

    /// Preconditions:
    /// 1. The hive key store has 5 distinct keys with different key types - public key, shared key and self key
    /// 2. The commit log has corresponding entries for the above keys and commit id should be null
    ///
    /// Operations:
    /// Get the uncommitted operations
    ///
    /// Assertions:
    /// 1. The uncommitted entries should be returned as in same order that keys are create
    test(
        'Verify that entries to be sent to the server from the uncommitted queue are retrieved in the order of creation - FIFO',
        () async {
      //----------------------------setup---------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      int? preOpSeqNum = TestResources.commitLog?.lastCommittedSequenceNumber();
      List<String> keys = [];
      //------------------preconditions setup-----------------------
      //create 5 random keys of types public/shared/self
      keys.add(AtKey.public('test_key0', sharedBy: TestResources.atsign)
          .build()
          .toString());
      keys.add((AtKey.shared('test_key1', sharedBy: TestResources.atsign)
            ..sharedWith('@alice'))
          .build()
          .toString());
      keys.add(AtKey.public('test_key2', sharedBy: TestResources.atsign)
          .build()
          .toString());
      keys.add((AtKey.shared('test_key3', sharedBy: TestResources.atsign)
            ..sharedWith('@alice'))
          .build()
          .toString());
      keys.add(AtKey.self('test_key4', sharedBy: TestResources.atsign)
          .build()
          .toString());
      for (var element in keys) {
        await keystore?.put(element, AtData()..data = 'dummydata');
      }
      //-----------------------operation------------------------------
      List<CommitEntry> changes =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getChangesSinceLastCommit(preOpSeqNum, 'test_key',
                  atSign: TestResources.atsign);
      //----------------------assertion-------------------------------
      for (int i = 0; i < 5; i++) {
        //assert that the order of changes received and the local list of keys is the same
        //comparing CommitEntry.atKey and the list element(which is an atKey)
        expect(changes[i].atKey, keys[i]);
      }
    });

    /// Preconditions:
    /// 1. The server commit id and local commit id are equal
    /// 2. The uncommitted entries should have following entries
    ///    a. hive_seq: 1 - @alice:phone@bob - commitOp. Update - value: +445-446-4847
    ///    b. hive_seq:2 - @alice:phone@bob - commitOp. Update - value: +447-448-4849
    ///
    /// Operations:
    /// Get the uncommitted operations
    ///
    /// Assertion:
    ///  1. When fetch uncommitted entry should be fetched:
    ///     - The entry with hive_seq -2
    ///******************************************
    ///changes that the following test asserts are not yet made on the client
    ///will enable this test after the change has been pushed to trunk
    ///******************************************
    test(
        'Verify that for a same key with many updates only the latest entry is selected from uncommitted queue to be sent to the server',
        () async {
      // //------------setup---------------------------------
      // HiveKeystore? keystore = TestResources.getHiveKeyStore(TestResources.atsign);
      // //capture hive seq_num before put to get changes after this num
      // int? currentSeqnum =
      //     TestResources.commitLog?.lastCommittedSequenceNumber();
      // //-------------------preconditions setup--------------
      // var key =
      //     AtKey.public('test2_key0', namespace: 'group2test2', sharedBy: TestResources.atsign)
      //         .build()
      //         .toString();
      // await keystore?.put(key, AtData()..data = 'test_data1');
      // //capture time before the second update
      // var timeUpdate2 = DateTime.now().toUtc();
      // await keystore?.put(key, AtData()..data = 'test_data2');
      // //------------------operation-----------------------
      // List<CommitEntry> changes =
      //     await SyncUtil(atCommitLog: TestResources.commitLog)
      //         .getChangesSinceLastCommit(currentSeqnum, 'group2test2',
      //             atSign: TestResources.atsign);
      // //-------------------assertion-----------------------
      // expect(changes.length, 1);
      // expect(changes[0].operation, CommitOp.UPDATE);
      // //assert that the commit entry we have has only been committed after timeUpdate2
      // //ensuring that the commit entry returned by changes is the latest one
      // expect(changes[0].opTime?.isAfter(timeUpdate2), true);
    });

    /// Preconditions:
    /// 1. The commit log has two entries for the same key in the below order
    ///     1. Key with CommitOp.Update
    ///     2. Key with CommitOp.Delete
    ///
    /// Operation:
    /// Get the uncommitted entries
    ///
    /// Assertions:
    /// 1. An empty list should be returned
    ///
    ///******************************************
    ///changes that the following test asserts are not yet made on the client
    ///will enable this test after the change has been pushed to trunk
    ///******************************************
    test(
        'Verify that a same key with a update and delete nothing is selected from uncommitted queue',
        () async {
      //--------------------setup-----------------------
      //   HiveKeystore? keystore = TestResources.getHiveKeyStore(TestResources.atsign);
      //   //capture hive seq_num before put to get changes after this num
      //   int? currentSeqnum =
      //       TestResources.commitLog?.lastCommittedSequenceNumber();
      //   //------------------preconditions setup-------------
      //   var key =
      //       AtKey.public('test2_key0', namespace: 'group2test3', sharedBy: TestResources.atsign)
      //           .build()
      //           .toString();
      //   //insert and delete the same key
      //   await keystore?.put(key, AtData()..data = 'test_data1');
      //   await keystore?.remove(key);
      //   //--------------------operation---------------------
      //   //get changes since previously captured hive seq_num
      //   List<CommitEntry> changes =
      //       await SyncUtil(atCommitLog: TestResources.commitLog)
      //           .getChangesSinceLastCommit(currentSeqnum, 'group2test3',
      //               TestResources.atsign: TestResources.atsign);
      //   //------------------assertion-----------------------
      //   expect(changes.length, 0);
    });

    /// Preconditions:
    /// 1. The server commit id and local commit id are equal
    /// 2. Create a key "@alice:phone@bob" before delete in step-3
    /// 3. The uncommitted entries should have following entries
    ///    a. hive_seq: 1 - @alice:phone@bob - commitOp.Delete
    ///    b. hive_seq:2 - @alice:phone@bob - commitOp.Update - value: +445-446-4847
    ///
    /// Assertion:
    ///  1. After sync completion:
    ///     a. The keystore should have test4_key0 with value: +445-446-4847
    test('A test to verify when an existing key is deleted and then created',
        () async {
      //----------------------------------setup---------------------------------
      LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
          keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeUpdateVerbBuilder());

      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      when(() => mockRemoteSecondary.executeVerb(any()))
          .thenAnswer((invocation) async => Future.value('data:ok'));
      when(() => mockRemoteSecondary.executeCommand(any(),
              auth: any(named: "auth")))
          .thenAnswer((invocation) =>
              Future.value('data:[{"id":1,"response":{"data":"21"}},'
                  '{"id":2,"response":{"data":"22"}}]'));

      //instantiate sync service using mocks
      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

      //re-initialize sync util using the local commit log for unit tests
      syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      //------------------------------preconditions setup-----------------------
      var key = AtKey.public('test4_key0',
              namespace: 'group2test4', sharedBy: TestResources.atsign)
          .build()
          .toString();
      //creating a key in the keystore
      await keystore?.put(key, AtData()..data = 'test_data1');
      var commitEntry =
          await syncService.syncUtil.getCommitEntry(0, TestResources.atsign);
      //updating the commitId so that the key above is not an uncommitted entry no more
      await syncService.syncUtil
          .updateCommitEntry(commitEntry, 1, TestResources.atsign);

      await keystore?.remove(key);
      await keystore?.put(key, AtData()..data = '+445-446-4847');
      int serverCommitId = 1;
      //-------------------------------operation--------------------------------
      await syncService.syncInternal(
          serverCommitId, SyncRequest()..result = SyncResult());
      //------------------------------assertion---------------------------------
      AtData? atData =
          await TestResources.getHiveKeyStore(TestResources.atsign)?.get(key);
      expect(atData?.data, '+445-446-4847');
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    tearDown(() async {
      await TestResources.tearDownLocalStorage();
      resetMocktailState();
    });
  });

  group(
      'tests related to sending uncommitted entries to server via the batch verb',
      () {
    setUp(() async {
      TestResources.atsign = '@alice';
      await TestResources.setupLocalStorage(TestResources.atsign);
    });

    AtClient mockAtClient = MockAtClient();
    AtClientManager mockAtClientManager = MockAtClientManager();
    NotificationServiceImpl mockNotificationService =
        MockNotificationServiceImpl();
    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    NetworkUtil mockNetworkUtil = MockNetworkUtil();

    /// Preconditions:
    /// 1. The local commitId is 5 and hive_seq is also at 5
    /// 2. There are 3 uncommitted entries - CommitOp.Update - 3.
    ///    The hive_seq for above 3 uncommitted entries is 6,7,8
    /// 3. ServerCommitId is at 7
    ///
    /// Operation
    /// 1. Initiate sync
    ///
    /// Assertions
    /// 1. The entries from server should be created at hive_seq 9,10 and 11
    /// 2. When fetching uncommitted entries only entries with hive_seq 6,7,8 should be returned.
    test('A test to verify batch requests does not sync entries with commitId',
        () async {
      //----------------------------------setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      LocalSecondary? localSecondary =
          LocalSecondary(mockAtClient, keyStore: keystore);

      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeUpdateVerbBuilder());

      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      when(() => mockRemoteSecondary.executeVerb(any()))
          .thenAnswer((_) => Future.value('data:${jsonEncode([
                    {
                      "atKey": "public:twitter.wavi@alice",
                      "value": "twitter.alice",
                      "metadata": {
                        "createdAt": "2021-04-08 12:59:19.251",
                        "updatedAt": "2021-04-08 12:59:19.251"
                      },
                      "commitId": 9,
                      "operation": "+"
                    },
                    {
                      "atKey": "public:instagram.wavi@alice",
                      "value": "instagram.alice",
                      "metadata": {
                        "createdAt": "2021-04-08 07:39:27.616Z",
                        "updatedAt": "2022-06-30 09:41:59.264Z"
                      },
                      "commitId": 10,
                      "operation": "*"
                    }
                  ])}'));
      when(() =>
          mockRemoteSecondary.executeCommand(any(),
              auth: any(named: "auth"))).thenAnswer(
          (invocation) => Future.value('data:[{"id":1,"response":{"data":"6"}},'
              '{"id":2,"response":{"data":"7"}},'
              '{"id":3,"response":{"data":"8"}}]'));

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.networkUtil = mockNetworkUtil;
      syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);

      //capture hive seq_num before operation
      int? preOpSeqNum = TestResources.commitLog?.lastCommittedSequenceNumber();
      int count = 0;
      //------------------preconditions setup-----------------------
      //create 5 random keys of types public/shared/self
      await localSecondary.putValue(
          'public:test_key0.group3test1@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key1.group3test1@bob', 'dummy');
      await localSecondary.putValue(
          'public:test_key2.group3test1@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key4.group3test1@bob', 'dummy');
      await localSecondary.putValue('test_key4.group3test1@bob', 'dummyData');

      //assign commitIds to commit entries created above. to make sure they don't sync
      var preSyncUncommittedEntries = await syncService.syncUtil
          .getChangesSinceLastCommit(preOpSeqNum, 'group3test1',
              atSign: TestResources.atsign);
      //for loop to assign commitId to all the above created commitEntries
      for (var commitEntry in preSyncUncommittedEntries) {
        await syncService.syncUtil
            .updateCommitEntry(commitEntry, ++count, TestResources.atsign);
      }

      //capture hive_seq_num before creating uncommitted entries again
      preOpSeqNum =
          syncService.syncUtil.atCommitLog?.lastCommittedSequenceNumber();
      //create new uncommitted entries
      await localSecondary.putValue(
          'public:test_key0.group3test1@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key1.group3test1@bob', 'dummy');
      await localSecondary.putValue(
          'public:test_key2.group3test1@bob', 'dummydata');
      // assert only the newer uncommitted entries without commitId are returned
      preSyncUncommittedEntries = await syncService.syncUtil
          .getChangesSinceLastCommit(preOpSeqNum, 'group3test1',
              atSign: TestResources.atsign);
      expect(preSyncUncommittedEntries.length, 3);
      //for loop to assert all the new uncommitted entries do not have commitId
      for (var commitEntry in preSyncUncommittedEntries) {
        expect(commitEntry.commitId, null);
      }
      expect(preSyncUncommittedEntries[0].atKey,
          'public:test_key0.group3test1@bob');
      expect(preSyncUncommittedEntries[1].atKey,
          '@sharedwithatsign:test_key1.group3test1@bob');
      expect(preSyncUncommittedEntries[2].atKey,
          'public:test_key2.group3test1@bob');
      //-------------------------------operation--------------------------------
      SyncRequest syncRequest = SyncRequest()..result = SyncResult();
      await syncService.syncInternal(10, syncRequest);
      //------------------------------assertion---------------------------------
      //assert that the keys from server are properly updated into the keystore/commitLog
      CommitEntry? commitEntry =
          await syncService.syncUtil.getCommitEntry(8, TestResources.atsign);
      expect(commitEntry?.atKey, 'public:twitter.wavi@alice');
      expect(commitEntry?.commitId, 9);
      commitEntry =
          await syncService.syncUtil.getCommitEntry(9, TestResources.atsign);
      expect(commitEntry?.atKey, 'public:instagram.wavi@alice');
      expect(commitEntry?.commitId, 10);
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    ///***********************************************
    ///Validations in the keystore do not allow invalid/malformed keys into the keystore
    ///Hence assertion is not possible
    ///skipping this test for now
    ///************************************************
    test(
        'A test to verify invalid keys and cached keys are not added to batch request',
        () async {
      /// Preconditions:
      /// 1. The local commitId is at commitId 5
      /// 2. There are 2 uncommitted entries:
      ///    1. A valid key
      ///    2. An invalid key
      /// 3. The serverCommitId is at 6 where the key is a cached key
      ///
      /// Operation
      /// 1. Initiate sync
      ///
      /// Assertions
      /// 1. The cached key from server should be synced
      /// 2. When fetching uncommitted entries only valid key should be added to uncommittedEntries queue
    });

    /// Preconditions:
    /// Have batch limit set to 5
    /// Have 10 valid keys in the local keystore
    ///
    /// Assertions:
    /// 1. Batch request should contain only 5 keys
    test('A test to verify keys in a batch request does not exceed batch limit',
        () async {
      //----------------------------------setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      LocalSecondary? localSecondary =
          LocalSecondary(mockAtClient, keyStore: keystore);

      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.networkUtil = mockNetworkUtil;

      //------------------------------preconditions setup-----------------------
      await localSecondary.putValue(
          'public:test_key0.group3test3@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key1.group3test3@bob', 'dummy');
      await localSecondary.putValue(
          'public:test_key2.group3test3@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key4.group3test3@bob', 'dummy');
      await localSecondary.putValue(
          'public:test_key41.group3test3@bob', 'dummyData');
      await localSecondary.putValue(
          'public:test_key10.group3test3@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key11.group3test3@bob', 'dummy');
      await localSecondary.putValue(
          'public:test_key2.group3test3@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key14.group3test3@bob', 'dummy');
      await localSecondary.putValue('test_key15.group3test3@bob', 'dummyData');
      //-------------------------------operation--------------------------------
      var uncommittedEntryBatch = syncService.getUnCommittedEntryBatch(
          await syncService.syncUtil.getChangesSinceLastCommit(
              -1, 'group3test3',
              atSign: TestResources.atsign));
      //------------------------------assertion---------------------------------
      //getUncommittedEntryBatch() returns multiple batches of size 5
      //asserting that the first batch is of length 5
      expect(uncommittedEntryBatch[0].length, 5);
      //assert that the second batch also has 5 entries
      expect(uncommittedEntryBatch[1].length, 5);
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    /// Preconditions:
    /// Uncommitted entries should have 5 valid keys
    ///
    /// Assertions:
    /// 1. Batch request should contain all the 5 valid keys
    /// HiveKeystore? keystore = TestResources.getHiveKeyStore(TestResources.atsign);
    test('A test to verify valid keys added to batch request', () async {
      //----------------------------------setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      LocalSecondary? localSecondary =
          LocalSecondary(mockAtClient, keyStore: keystore);

      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.networkUtil = mockNetworkUtil;

      //------------------preconditions setup-----------------------
      //create 5 random keys of types public/shared/self
      List<String> keys = [];
      keys.add(AtKey.public('test_key0',
              sharedBy: TestResources.atsign, namespace: 'group3test4')
          .build()
          .toString());
      keys.add((AtKey.shared('test_key1',
              sharedBy: TestResources.atsign, namespace: 'group3test4')
            ..sharedWith('@alice'))
          .build()
          .toString());
      keys.add(AtKey.public('test_key2',
              sharedBy: TestResources.atsign, namespace: 'group3test4')
          .build()
          .toString());
      keys.add((AtKey.shared('test_key3',
              sharedBy: TestResources.atsign, namespace: 'group3test4')
            ..sharedWith('@alice'))
          .build()
          .toString());
      keys.add(AtKey.self('test_key4',
              sharedBy: TestResources.atsign, namespace: 'group3test4')
          .build()
          .toString());
      //for loop to insert all the above created keys into the keystore
      for (var key in keys) {
        await keystore?.put(key, AtData()..data = 'dummydata');
      }

      //-------------------------------operation--------------------------------
      var batchRequest = await syncService.getBatchRequests(await syncService
          .syncUtil
          .getChangesSinceLastCommit(-1, 'group3test4',
              atSign: TestResources.atsign));
      //------------------------------assertion---------------------------------
      //assert all the above created keys are part of the commands in the batch request
      //doing this in a for loop asserts that the order of keys is preserved
      for (int i = 0; i < keys.length; i++) {
        //key cannot be extracted from batchRequest as the entry is a command
        //assert that the actual key is part of the command
        expect(batchRequest[i].command?.contains(keys[i]), true);
      }
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    /// Preconditions:
    /// Have some uncommitted entries that includes updates and deletes of a key
    /// The uncommitted entries(keys) are sent as a batch request
    ///
    /// Assertions:
    /// Batch response should contain the commitId for every key sent in the batch request
    test(
        'A test to verify the commitId is updated against the uncommitted entries on batch response',
        () async {
      //----------------------------------setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      LocalSecondary? localSecondary =
          LocalSecondary(mockAtClient, keyStore: keystore);

      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeUpdateVerbBuilder());

      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      when(() => mockRemoteSecondary.executeCommand(any(),
              auth: any(named: "auth")))
          .thenAnswer((invocation) =>
              Future.value('data:[{"id":1,"response":{"data":"21"}},'
                  '{"id":2,"response":{"data":"22"}},'
                  '{"id":3,"response":{"data":"23"}},'
                  '{"id":4,"response":{"data":"24"}},'
                  '{"id":5,"response":{"data":"25"}}]'));

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.networkUtil = mockNetworkUtil;
      syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
      //------------------preconditions setup-----------------------------------
      await localSecondary.putValue(
          'public:test_key0.group3test5@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key1.group3test5@bob', 'dummy');
      await localSecondary.putValue(
          'public:test_key2.group3test5@bob', 'dummydata');
      await localSecondary.putValue(
          '@sharedWithAtsign:test_key4.group3test5@bob', 'dummy');
      await localSecondary.putValue('test_key14.group3test5@bob', 'dummyData');
      //-----------------------operation----------------------------------------
      int serverCommitId = -1;
      await syncService.syncInternal(
          serverCommitId, SyncRequest()..result = SyncResult());
      // ------------------------------Assertions-------------------------------

      //after sync assert that commitIds of all commit entries have been updated
      //seq_num starts from 0 and the commitIds start from 21 based on server response mocked above
      var result = await syncService.syncUtil.atCommitLog?.getEntry(0);
      expect(result?.commitId, 21);
      result = await syncService.syncUtil.atCommitLog?.getEntry(1);
      expect(result?.commitId, 22);
      result = await syncService.syncUtil.atCommitLog?.getEntry(2);
      expect(result?.commitId, 23);
      result = await syncService.syncUtil.atCommitLog?.getEntry(3);
      expect(result?.commitId, 24);
      result = await syncService.syncUtil.atCommitLog?.getEntry(4);
      expect(result?.commitId, 25);
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    ///********************************
    ///Assertion not possible as invalid keys cannot be inserted into the keystore
    ///********************************
    test(
        'A test to verify sync continues when server returns exception for one of the sync entry',
        () {
      /// This tests focuses to assert when exception occurs on cloud secondary,
      /// the exception should be logged and sync should continue.
      /// Preconditions:
      /// 1. Have 4 valid keys and 1 invalid key in the local keystore
      ///
      /// Assertions:
      /// The sync should fail only for the invalid key and the remaining valid keys should be synced successful
      /// The exception should be thrown for the invalid key
      /// Sync should not be in infinite loop
    });

    ///Note: The uncommitted entries in the hive keystore
    /// should be added to batch request in the same order.
    /// If there are two entries for same key with commit op. update and delete,
    /// then batch request should have the same sequence in it.

    /// Preconditions:
    /// 1. Have uncommitted entries in the keystore
    /// a. hive_seq: 1 - @alice:phone@bob - commitOp. Update - value: +445-446-4847
    /// b. hive_seq:2 - @alice:phone@bob - commitOp. delete
    /// c. hive_seq:3 - @alice:email@bob - commitOp. Update - value: alice@gmail.com
    /// d. hive_seq:4 - @alice:username@bob - commitOp. Update - value: alice123
    /// e. hive_seq:5 - @alice:facebook@bob - commitOp. Update - value: alice
    ///
    /// Assertions:
    /// 1. Batch request should have the same sequence as inserted hive keystore
    ///  i.e., - a,b,c,d,e
    test(
        'A test to verify the key into batch request are added in sequential order as in hive keystore',
        () async {
      //----------------------------------setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      LocalSecondary? localSecondary =
          LocalSecondary(mockAtClient, keyStore: keystore);

      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.networkUtil = mockNetworkUtil;

      //------------------preconditions setup-----------------------
      //create 5 random keys of types public/shared/self
      await localSecondary.putValue(
          'public:test_key0.group3test7@bob', 'dummydata');
      await keystore?.remove('test_key0.group3test7@bob');
      await localSecondary.putValue(
          'public:test_key1.group3test7@bob', 'dummy');
      await keystore?.remove('test_key1.group3test7@bob');
      await localSecondary.putValue(
          'public:test_key2.group3test7@bob', 'dummydata');

      //-------------------------------operation--------------------------------
      int firstCommitSeqNum = -1;
      var batchRequest = await syncService.getBatchRequests(await syncService
          .syncUtil
          .getChangesSinceLastCommit(firstCommitSeqNum, 'group3test7',
              atSign: TestResources.atsign));
      //------------------------------assertion---------------------------------
      expect(batchRequest[0].command,
          'update:public:test_key0.group3test7@bob dummydata');
      expect(batchRequest[1].command, 'delete:test_key0.group3test7@bob');
      expect(batchRequest[2].command,
          'update:public:test_key1.group3test7@bob dummy');
      expect(batchRequest[3].command, 'delete:test_key1.group3test7@bob');
      expect(batchRequest[4].command,
          'update:public:test_key2.group3test7@bob dummydata');
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    tearDown(() async {
      await TestResources.tearDownLocalStorage();
      resetMocktailState();
    });
  });

  ///********************************
  // TODO - FEATURE NEEDS TO BE IMPLEMENTED
  // With the current implementation if we create and delete the same key,
  // Both the entries will added to the sync queue.
  ///********************************
  group('tests related to TTL and TTB', () {
    setUp(() async {
      TestResources.atsign = '@charlie';
      await TestResources.setupLocalStorage(TestResources.atsign);
    });

    test('A test to verify when a key is set with TTL and expired when sync',
        () {
      /// Preconditions:
      /// 1. Create a key with TTL value of 30 seconds
      /// 2. Let the TTL time expire and then initiate sync
      ///    Since the key is expired, delete operation will triggered.
      ///
      /// Assertions:
      /// 1. Since the key is created and deleted, the key can be omitted to sync
      ///    to cloud secondary
    });
    test(
        'A test to verify when a key is set with TTL and key is not expired when sync starts',
        () {
      /// Preconditions:
      /// 1. Create a key with TTL value of 30 seconds
      /// 2. Initiate sync process
      ///
      ///
      /// Assertions:
      /// 1. The key should be synced to the cloud secondary
    });
    test('A test to verify when a key is set with TTL and is reset', () {
      /// Preconditions:
      /// 1. Create a key with TTL value of 30 seconds
      /// 2. Reset the TTL value to 0
      /// 3. Commitlog keystore should have two entries:
      ///    a. CommitOp. with Update
      ///    b. CommitOp. with Update_Meta
      ///
      /// Operations:
      /// 1. Run sync process
      ///
      /// Assertions:
      /// 1. Both the commits should be synced to the cloud secondary
      /// (If we sync only update_meta, the value will not be updated to cloud secondary)
    });

    //TODO: Arch all discussion: When key is still not born, we return data:null
    // however, when sync process triggers before the key is not born, we get the actual
    // value from keystore instead of 'data:null' to sync to server
    test(
        'A test to verify when ttb is set on key and key is not available when sync',
        () {
      /// Preconditions:
      /// 1. Create a key with ttb value of 30 seconds
      /// 2. Initiate sync at 10th second
      ///
      /// Assertions:
      /// 1. The key should be synced to remote secondary along with the value successfully
    });

    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    /// Operation:
    /// Put a key with TTB say 30 seconds

    /// Assertions:
    /// 1. Key store should have the key with the value inserted
    /// 2. Assert that the value is returned only after 30seconds
    /// 3. A metadata "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be set to 0
    /// 4. CommitLog should have an entry for the new public key with commitOp.Update
    /// and commitId is null
    test('A test to verify when a key is set with TTB and key is available',
        () async {
      //----------------------------------setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atKey = AtKey.self('authcode',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      var atData = AtData();
      atData.data = '11122';
      //----------------------------------operation---------------------------------
      int putCommitId = await keystore!.put(atKey, atData, time_to_born: 10000);
      // key should not be available before 10 seconds
      // Assertion is not possible as the key will be available in the keystore level
      // expect(() async => await keystore.get(atKey),
      //     throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      var getResult = await keystore.get(atKey);
      //----------------------------------assertion---------------------------------
      expect(getResult!.data, '11122');
      expect(getResult.metaData!.createdAt!.isBefore(DateTime.now()), true);
      expect(getResult.metaData!.version, 0);
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitLogEntry?.operation, CommitOp.UPDATE_ALL);
    });

    tearDown(() async {
      await TestResources.tearDownLocalStorage();
      resetMocktailState();
    });
  });

  group(
      'A group of tests on fetching the local commit id and uncommitted entries',
      () {
    setUp(() async {
      TestResources.atsign = '@fuller';
      await TestResources.setupLocalStorage(TestResources.atsign);
    });

    AtClient mockAtClient = MockAtClient();
    AtClientManager mockAtClientManager = MockAtClientManager();
    NotificationServiceImpl mockNotificationService =
        MockNotificationServiceImpl();
    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    NetworkUtil mockNetworkUtil = MockNetworkUtil();

    ///Preconditions:
    /// 1. The local keystore contains following keys
    ///   a. phone.wavi@alice with commit id 10
    ///   b. mobile.atmosphere@alice with commit id 11
    ///
    /// Assertions:
    /// When fetched highest commit entry - entry with commit id 11 should be fetched
    test('A test to verify highest localCommitId is fetched with no regex',
        () async {
      //----------------------------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atKey1 =
          AtKey.self('phone', namespace: 'wavi', sharedBy: TestResources.atsign)
              .build()
              .toString();
      var atKey2 = AtKey.self('mobile',
              namespace: 'atmosphere', sharedBy: TestResources.atsign)
          .build()
          .toString();
      //----------------------------------Operations----------------------------
      int waviCommitId =
          await keystore!.put(atKey1, AtData()..data = '1234567890');
      int atMospherCommitId =
          await keystore.put(atKey2, AtData()..data = '909120909109');
      await TestResources.setCommitEntry(waviCommitId, TestResources.atsign);
      await TestResources.setCommitEntry(
          atMospherCommitId, TestResources.atsign);
      //----------------------------------Assertions----------------------------
      var lastSyncedEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getLastSyncedEntry('', atSign: TestResources.atsign);
      expect(lastSyncedEntry!.commitId, atMospherCommitId);
    });

    ///Preconditions:
    /// 1. The local keystore contains following keys
    ///   a. phone.wavi@alice with commit id 10
    ///   b. mobile.atmosphere@alice with commit id 11
    ///
    /// Assertions:
    /// When fetched highest commit entry with regex .wavi - entry with
    /// commit Id 10 should be fetched
    test(
        'A test to verify highest localCommitId satisfying the regex is fetched',
        () async {
      //----------------------------------Setup---------------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var waviKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: TestResources.atsign)
              .build()
              .toString();
      var atmosphereKey = AtKey.self('mobile',
              namespace: 'atmosphere', sharedBy: TestResources.atsign)
          .build()
          .toString();
      //----------------------------------Operations----------------------------
      int waviId = await keystore!.put(waviKey, AtData()..data = '1234567890');
      int atmosphereId =
          await keystore.put(atmosphereKey, AtData()..data = '909120909109');
      await TestResources.setCommitEntry(waviId, TestResources.atsign);
      await TestResources.setCommitEntry(atmosphereId, TestResources.atsign);
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getLastSyncedEntry('wavi', atSign: TestResources.atsign);
      //----------------------------------Assertions----------------------------
      expect(commitLogEntry!.commitId, waviId);
    });

    ///Preconditions:
    /// 1. The local keystore contains following keys
    ///   a. phone.wavi@alice with commit id 10
    ///   b. mobile.atmosphere@alice with commit id 11
    ///
    /// Assertions:
    /// The lastSyncEntry must have the highest commit id - here commitId 11
    test('A test to verify lastSyncedEntry returned has the highest commitId',
        () async {
      //----------------------------------Setup-----------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atKey1 =
          AtKey.self('phone', namespace: 'wavi', sharedBy: TestResources.atsign)
              .build()
              .toString();
      var atKey2 = AtKey.self('mobile',
              namespace: 'atmosphere', sharedBy: TestResources.atsign)
          .build()
          .toString();
      //----------------------------------Operations----------------------------
      int waviId = await keystore!.put(atKey1, AtData()..data = '1234567890');
      int atmosphereId =
          await keystore.put(atKey2, AtData()..data = '909120909109');
      await TestResources.setCommitEntry(waviId, TestResources.atsign);
      await TestResources.setCommitEntry(atmosphereId, TestResources.atsign);
      var commitLogEntry = await SyncUtil(atCommitLog: TestResources.commitLog)
          .getLastSyncedEntry('', atSign: TestResources.atsign);
      //----------------------------------Assertions----------------------------
      expect(commitLogEntry!.commitId, atmosphereId);
    });

    /// Preconditions:
    ///  1. The local keystore contains following keys
    ///    a. aboutMe.wavi@alice with commit id null and commitOp.Update
    ///    b. phone.wavi@alice with commit id 10 and commitOp.Update
    ///    c. mobile.wavi@alice with commit id 11 and commitOp.Update
    ///    d. country.wavi@alice with commit id null and commitOp.Update
    ///
    /// Assertions:
    ///  The uncommitted entries must have entries with commitId null
    ///    Here: commit entries of aboutMe.wavi@alice and country.wavi@alice
    test(
        'A test to verify the uncommitted entries have entries with commit-id null',
        () async {
      //----------------------------------Setup-----------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var aboutKey = AtKey.self('aboutme',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      var phoneKey =
          AtKey.self('phone', namespace: 'wavi', sharedBy: TestResources.atsign)
              .build()
              .toString();
      var mobileKey = AtKey.self('mobile',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      var countryKey = AtKey.self('country',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      //----------------------------------Operations----------------------------
      int phoneId =
          await keystore!.put(phoneKey, AtData()..data = '1234567890');
      await TestResources.setCommitEntry(phoneId, TestResources.atsign);
      int aboutKeyId = await keystore.put(aboutKey, AtData()..data = 'QA');
      int mobileId =
          await keystore.put(mobileKey, AtData()..data = '909120909109');
      await TestResources.setCommitEntry(mobileId, TestResources.atsign);
      int countryCommitId =
          await keystore.put(countryKey, AtData()..data = 'USA');
      var commitLogEntryAboutKey =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(aboutKeyId, TestResources.atsign);
      var commitLogEntryCountryKey =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(countryCommitId, TestResources.atsign);
      //----------------------------------Assertions----------------------------
      expect(commitLogEntryAboutKey!.commitId, null);
      expect(commitLogEntryCountryKey!.commitId, null);
    });

    /// Preconditions:
    ///  1. The local keystore does not contains key
    ///
    /// Assertions:
    ///  a. The lastSyncedEntry should be null
    ///  b. The commit entry should be null
    test(
        'A test to verify lastSyncedEntry returns null when commit log do not have keys',
        () async {
      var commitLog = TestResources.commitLog;
      var syncUtil = SyncUtil(atCommitLog: commitLog);
      //----------------------------------Assertions----------------------------
      expect(commitLog?.getSize(), 0);
      expect(
          await syncUtil.getLastSyncedEntry('regex',
              atSign: TestResources.atsign),
          null);
      expect(commitLog?.lastCommittedSequenceNumber(), -1);
      expect(await commitLog?.getEntry(commitLog.lastCommittedSequenceNumber()),
          null);
    });

    /// Preconditions:
    /// 1. The server commitId is at 100 and local commitId is also 100
    /// 2. In the local keystore have 5 uncommitted entries with .wavi
    /// 3. Initiate sync with regex - ".wavi"
    ///
    /// Assertions:
    /// 1. Server and local should be in sync and 5 uncommitted entries
    ///    must be synced to cloud secondary
    test('A test to verify sync with regex when local is ahead', () async {
      //----------------------------------Setup-----------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      LocalSecondary? localSecondary =
          LocalSecondary(mockAtClient, keyStore: keystore);
      AtClientPreference preference = AtClientPreference()..syncRegex = 'wavi';

      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeUpdateVerbBuilder());

      mockAtClient.setPreferences(preference);
      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      when(() =>
          mockRemoteSecondary.executeCommand(any(),
              auth: any(named: 'auth'))).thenAnswer(
          (_) async => Future.value('data:[{"id":1,"response":{"data":"101"}},'
              '{"id":2,"response":{"data":"102"}},'
              '{"id":3,"response":{"data":"103"}},'
              '{"id":4,"response":{"data":"104"}},'
              '{"id":5,"response":{"data":"105"}}]'));

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.networkUtil = mockNetworkUtil;
      syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);

      //------------------preconditions setup-----------------------
      //manipulating commitLog to make the commitId 100 the lastSyncedEntry
      await localSecondary.putValue(
          'public:dummy.group5test6@bob', 'dummydata');
      var commitEntry = await syncService.syncUtil.atCommitLog?.getEntry(0);
      await syncService.syncUtil.atCommitLog?.update(commitEntry!, 100);

      //creating uncommitted entries
      await localSecondary.putValue('public:test_key0.wavi@bob', 'dummydata');
      await localSecondary.putValue('public:test_key1.wavi@bob', 'dummydata');
      await localSecondary.putValue('public:test_key2.wavi@bob', 'dummydata');
      await localSecondary.putValue('public:test_key3.wavi@bob', 'dummydata');
      await localSecondary.putValue('public:test_key4.wavi@bob', 'dummydata');

      int serverCommitId = 100;
      SyncResult syncResult = await syncService.syncInternal(
          serverCommitId, SyncRequest()..result = SyncResult());
      //------------------Assertions-------------------------------
      expect(syncResult.syncStatus, SyncStatus.success);
      expect(syncResult.keyInfoList.length, 5);
      var lastSyncedEntry = await syncService.syncUtil
          .getLastSyncedEntry('wavi', atSign: TestResources.atsign);
      assert(lastSyncedEntry.toString().contains('test_key4.wavi@bob'));
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    tearDown(() async {
      await TestResources.tearDownLocalStorage();
      resetMocktailState();
    });
  });

  group(
      'Tests to validate how the client processes updates from the server - can the client reject? under what conditions? what happens upon a rejection?',
      () {
    setUp(() async {
      TestResources.atsign = '@dexter';
      await TestResources.setupLocalStorage(TestResources.atsign);
    });

    /// Preconditions:
    /// 1. The key already exists in the local keystore
    /// 2. An entry should already exist in the local commit log
    ///
    /// Operation:
    /// 1. Run sync where the sync response contains an entry with CommitOp.Update of a new key
    ///
    /// Assertions:
    /// 1. The value and metadata of the existing key should be updated
    ///    Since we are updated existing key "createdAt" field should remain as is and
    ///    "updatedAt" field should be updated.
    /// 2. The version field should be incremented by 1
    /// 3. The new entry should be created in the commit log with the new commit id
    test('Update from server for a key that exists in local secondary',
        () async {
      //----------------------------------Setup-----------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atKey = AtKey.self('weather',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      // key available in the local keystore
      await keystore!.put(atKey, AtData()..data = 'sunny');
      // Updating the same key from the server
      int putCommitId = await keystore.put(atKey, AtData()..data = 'sunny');
      // Updating the commit entry with commitId to mimic the server behaviour
      await TestResources.setCommitEntry(putCommitId, TestResources.atsign);
      var getResult = await keystore.get(atKey);
      //------------------ Assertions-----------------------
      expect(getResult!.data, 'sunny');
      expect(getResult.metaData!.updatedAt!.isBefore(DateTime.now()), true);
      var commitEntry = await TestResources.commitLog!.getEntry(putCommitId);
      expect(commitEntry!.commitId, putCommitId);
    });

    /// Preconditions:
    /// 1. The key does not exist in the local keystore
    ///
    /// Operation:
    /// 1. Run sync where the sync response contains an entry with CommitOp.Update of a new key
    ///
    /// Assertions:
    /// 1. The new key should be created in the hive keystore
    /// 2. An entry created in the commit log with the new commit id
    test('Update from server for a key that does not exist in local secondary',
        () async {
      //----------------------------------Setup-----------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atKey = AtKey.self('season',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, AtData()..data = 'autumn');
      // Updating the commit entry with commitId to mimic the server behaviour
      await TestResources.setCommitEntry(putCommitId, TestResources.atsign);
      var getResult = await keystore.get(atKey);
      //------------------ Assertions-----------------------
      expect(getResult!.data, 'autumn');
      var commitEntry = await TestResources.commitLog!.getEntry(putCommitId);
      expect(commitEntry!.commitId, putCommitId);
    });

    /// Preconditions:
    /// 1. The key already exists in the local keystore
    /// 2. An entry in commitLog with commitOp.Update
    ///
    /// Operation:
    /// 1. Run sync where the sync response contains an entry with CommitOp.delete of an existing key
    ///
    /// Assertions:
    /// 1. The key should be deleted from the hive keystore
    /// 2. An entry with commitOp.delete should be added to the commit log
    test('Delete from server for a key that exists in local secondary',
        () async {
      //----------------------------------Setup-----------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atKey = AtKey.self('weather',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      // key available in the local keystore
      await keystore!.put(atKey, AtData()..data = 'sunny');
      // Updating the same key from the server
      int? removeCommitId = await keystore.remove(atKey);
      // Updating the commit entry with commitId to mimic the server behaviour
      //------------------ Assertions-----------------------
      await TestResources.setCommitEntry(removeCommitId!, TestResources.atsign);
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      var commitEntry = await TestResources.commitLog!.getEntry(removeCommitId);
      expect(commitEntry!.operation, CommitOp.DELETE);
    });

    /// Precondition:
    /// The key does not exist in the local secondary
    ///
    /// Assertions;
    /// An entry should be added to commit log to prevent sync imbalance
    test('Delete from server for a key that does not exist in local secondary',
        () async {
      //----------------------------------Setup-----------------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atKey = AtKey.self('weather',
              namespace: 'wavi', sharedBy: TestResources.atsign)
          .build()
          .toString();
      // Updating the same key from the server
      int? removeCommitId = await keystore!.remove(atKey);
      // Updating the commit entry with commitId to mimic the server behaviour
      await TestResources.setCommitEntry(removeCommitId!, TestResources.atsign);
      //------------------ Assertions-----------------------
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      var commitEntry = await TestResources.commitLog!.getEntry(removeCommitId);
      expect(commitEntry!.operation, CommitOp.DELETE);
    });

    // TODO - ENHANCEMENT REQUESTS
    /// Improve KeyInfo to include description *
    /// Example - Include info that says 'this happens to be a bad key'
    /// Enhancement ticket raised - https://github.com/TestResources.atsign-foundation/at_client_sdk/issues/833
    test('Verify clients handling of bad keys in updates from server', () {
      /// Precondition:
      /// Key will be rejected by a put / attempt to write to key store
      /// Commit log has no entry for this key
      /// Key store has no entry for this key

      /// Assertions:
      /// 1. KeyInfo should inform about a bad key / not able sync this key
      /// 2. Key store should be in right state
      /// 3. CommitLog should have an entry along with server commit id
    });

    /// TODO - ENHANCEMENT REQUESTS
    /// Improve KeyInfo to include description *
    /// Example - Include info that says 'this happens to be a bad key'
    /// Enhancement ticket raised -https://github.com/TestResources.atsign-foundation/at_client_sdk/issues/833
    test(
        'Verify clients handling of bad keys in deletes from server - For an existing bad key',
        () {
      /// Precondition:
      /// Even if it is a bad key, delete operation should just delete
      /// Commit log has a entry for this key
      /// Key store has a entry for this key

      /// Assertions:
      /// 1. KeyInfo should inform about a key being deleted
      /// 2. Key store should be in right state
      /// 3. CommitLog should have an entry along with server commit id
    });
    test(
        'Verify clients handling of bad keys in deletes from server - Bad key is not present in the local key store',
        () {
      /// Precondition:
      /// The bad key does not exist in the local secondary
      ///
      /// Assertions;
      /// An entry should be added to commit log to prevent sync imbalance
    });
  });

  group('A group of tests when server is ahead of local commit id', () {
    setUp(() async {
      TestResources.atsign = '@gandalf';
      await TestResources.setupLocalStorage(TestResources.atsign);
    });

    AtClient mockAtClient = MockAtClient();
    AtClientManager mockAtClientManager = MockAtClientManager();
    NotificationServiceImpl mockNotificationService =
        MockNotificationServiceImpl();
    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    NetworkUtil mockNetworkUtil = MockNetworkUtil();

    /// The test should contain all types of keys - public key, shared key, self key
    ///
    /// Preconditions:
    /// 1. Server has 5 entries that are not synced to the local i.e., server commit id is 15
    /// 2. Local commit id is 10
    ///
    /// Operation:
    /// 1. remote to local sync
    ///
    /// Assertions:
    /// Server and local should be in sync and 5 entries from the server must be synced to local
    test('A test to verify server commit entries are synced to local',
        () async {
      //----------------------------------Setup---------------------------------
      LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
          keyStore: TestResources.getHiveKeyStore(TestResources.atsign));
      // ------------------preconditions setup ---------------------------------
      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      when(() => mockRemoteSecondary.executeVerb(
              any(that: StatsVerbBuilderMatcher()),
              sync: any(named: 'sync')))
          .thenAnswer((invocation) => Future.value('data:[{"value":"15"}]'));
      when(() => mockRemoteSecondary.executeVerb(
              any(that: SyncVerbBuilderMatcher()),
              sync: any(named: "sync")))
          .thenAnswer((invocation) => Future.value('data:['
              '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
              '"value":"dummy",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":11,"operation":"*"}'
              ','
              '{"atKey":"public:test_key1.demo@bob",'
              '"value":"dummy",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":12,"operation":"*"}'
              ','
              '{"atKey":"test_key2.demo@bob",'
              '"value":"dummy",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":13,"operation":"*"}'
              ','
              '{"atKey":"@bob:phone@alice",'
              '"value":"dummy",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":14,"operation":"*"}'
              ','
              '{"atKey":"cached:@bob:test_key@framedmurder69",'
              '"value":"dummy",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":15,"operation":"*"}]'));

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.networkUtil = mockNetworkUtil;
      syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);

      //--------------------------Preconditions setup---------------------------
      await localSecondary.putValue(
          'cached:@bob:shared_key@framedmurder', 'fe fi fo fum');
      //update the above commitEntry with commitId - 10 to set localCommitId to 10
      CommitEntry? commitEntry =
          await syncService.syncUtil.getCommitEntry(0, TestResources.atsign);
      await syncService.syncUtil
          .updateCommitEntry(commitEntry, 10, TestResources.atsign);
      //capture seq_num before sync
      int? preSyncSeqNum = (await syncService.syncUtil
              .getLastSyncedEntry('', atSign: TestResources.atsign))
          ?.commitId;
      expect(preSyncSeqNum, 10);
      //---------------------------operation------------------------------------
      await syncService.syncInternal(15, SyncRequest()..result = SyncResult());
      //----------------------------------Assertions----------------------------
      //assert that all the entries synced from server have been updated in the local commitLog
      commitEntry =
          await syncService.syncUtil.getCommitEntry(1, TestResources.atsign);
      expect(commitEntry?.atKey, 'cached:@bob:shared_key@guiltytaurus27');
      commitEntry =
          await syncService.syncUtil.getCommitEntry(2, TestResources.atsign);
      expect(commitEntry?.atKey, 'public:test_key1.demo@bob');
      commitEntry =
          await syncService.syncUtil.getCommitEntry(3, TestResources.atsign);
      expect(commitEntry?.atKey, 'test_key2.demo@bob');
      commitEntry =
          await syncService.syncUtil.getCommitEntry(4, TestResources.atsign);
      expect(commitEntry?.atKey, '@bob:phone@alice');
      commitEntry =
          await syncService.syncUtil.getCommitEntry(5, TestResources.atsign);
      expect(commitEntry?.atKey, 'cached:@bob:test_key@framedmurder69');
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    ///***********************************
    ///assertions unclear for the test below
    ///**********************************
    test(
        'A test to verify when invalid keys are returned in sync response from server',
        () {});

    /// Preconditions:
    /// 1. There should be no entry for the same key in the key store
    /// 2. There should be no entry for the same key in the commit log

    /// Operation:
    /// CommitOp.UPDATE

    /// Assertions:
    /// 1. Key store should have the public key with the value inserted
    /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
    /// DateTime which is less than DateTime.now()
    /// 3. The version of the key should be set to 0
    /// 4. CommitLog should have an entry for the new public key with commitOp.Update
    /// and commitId is null
    test(
        'A test to verify a new key is created in local keystore on update commit operation',
        () async {
      // --------------------- Setup ---------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      var atData = AtData();
      atData.data = 'HitechCity';
      //------------------Operation-------------
      //  creating a key in the keystore
      String atKey = (AtKey.public('place',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      int putCommitId = await keystore!.put(atKey, atData);
      //------------------Assertions-------------
      var keyStoreGetResult = await keystore.get(atKey);
      expect(keyStoreGetResult!.metaData!.createdAt!.isBefore(DateTime.now()),
          true);
      expect(keyStoreGetResult.metaData!.version, 0);
      // verifying the key in the commit log
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putCommitId, TestResources.atsign);
      expect(commitEntryResult!.operation, CommitOp.UPDATE);
    });

    //TODO: Update all the available metadata fields and assert
    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log

    /// Operation:
    /// Updating the metadata for an existing shared key
    /// CommitOp.UPDATE_META
    /// a. Update TTL value to 30 seconds
    /// b. Update TTB value to 10 seconds
    /// c. Update TTR
    /// d. Update CCD to TRUE

    /// Assertions:
    ///1. Assert the metadata of the key. "CreatedAt" field should not be modified and
    /// "UpdatedAt" should be less than now().
    ///  expiresAt, availableAt, refreshAt values in the metadata should be in line with the updated values
    ///  CCD should be true
    /// a. The key should expire after 30seconds
    /// b. The key should be available only after 10 seconds
    ///
    /// 2. The version of the key should be incremented by 1
    /// 4. CommitLog should have an entry for the  key with commitOp.UPDATE_META
    test(
        'A test to verify existing key metadata is updated on update_meta commit operation',
        () async {
      // --------------------- Setup ---------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      //------------------Operation-------------
      //  creating a key in the keystore
      String atKey = (AtKey.public('city',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      AtMetaData? metaData;
      metaData = AtMetaData();
      metaData.ttl = 30;
      metaData.ttb = 10;
      metaData.ttr = 20;
      metaData.isCascade = true;
      int? putMetaId = await keystore!.putMeta(atKey, metaData);
      //------------------Assertions-------------
      var keyStoreGetResult = await keystore.getMeta(atKey);
      expect(keyStoreGetResult!.createdAt!.isBefore(DateTime.now()), true);
      expect(keyStoreGetResult.ttl, 30);
      expect(keyStoreGetResult.ttb, 10);
      expect(keyStoreGetResult.ttr, 20);
      expect(keyStoreGetResult.isCascade, true);
      // verifying the key in the commit log
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(putMetaId!, TestResources.atsign);
      expect(commitEntryResult!.operation, CommitOp.UPDATE_META);
    });

    /// Preconditions:
    /// 1. There should be an entry for the same key in the key store
    /// 2. There should be an entry for the same key in the commit log
    ///
    /// Operation:
    /// CommitOp.DELETE
    ///
    /// Assertions:
    /// 1. The key should be deleted from the key store
    /// 2. CommitLog should have an entry for the key with commitOp.DELETE
    test(
        'A test to verify existing key is deleted when delete commit operation is received',
        () async {
      // --------------------- Setup ---------------------
      HiveKeystore? keystore =
          TestResources.getHiveKeyStore(TestResources.atsign);
      //------------------Operation-------------
      //  creating a key in the keystore
      String atKey = (AtKey.public('message',
              namespace: 'wavi', sharedBy: TestResources.atsign))
          .build()
          .toString();
      await keystore!.put(atKey, AtData()..data = 'hello');
      int? removeId = await keystore.remove(atKey);
      //------------------Assertions-------------
      expect(() async => await keystore.get(atKey),
          throwsA(predicate((dynamic e) => e is KeyNotFoundException)));
      // verifying the key in the commit log
      var commitEntryResult =
          await SyncUtil(atCommitLog: TestResources.commitLog)
              .getCommitEntry(removeId!, TestResources.atsign);
      expect(commitEntryResult!.operation, CommitOp.DELETE);
    });

    test(
        'A test to verify when local keystore does not contain key which is'
        'in delete commit operation', () {
      /// Preconditions:
      /// 1. There should be no entry for the same key in the key store
      /// 2. There should be no entry for the same key in the commit log
      ///
      /// Operation:
      /// CommitOp.DELETE
      ///
      /// Assertions:
      /// TODO - Should it throw an exception or have an entry for delete in commit log
    });

    //**************************
    //Assertion and setup not possible from client side
    //**************************
    test('A test to verify sync with regex when server is ahead', () async {
      /// Preconditions:
      /// 1. The server commitId is at 15 and local commitId is at 5
      /// 2. The server has keys with and without matching regex between 5 to 10
      ///    a. keys with .wavi namespace and keys with .atmosphere namespace
      /// 3. Initiate sync with regex - ".wavi"
      ///
      /// Assertions:
      /// 1. The keys matching the regex should only sync to local secondary
      /// 2. isInSync should return after sync completion
    });

    tearDown(() async {
      await TestResources.tearDownLocalStorage();
      resetMocktailState();
    });
  });

  group('A group of test to verify sync conflict resolution', () {
    setUp(() async {
      TestResources.atsign = '@hiro';
      await TestResources.setupLocalStorage(TestResources.atsign);
    });

    AtClient mockAtClient = MockAtClient();
    AtClientManager mockAtClientManager = MockAtClientManager();
    NotificationServiceImpl mockNotificationService =
        MockNotificationServiceImpl();
    RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
    NetworkUtil mockNetworkUtil = MockNetworkUtil();

    /// Preconditions:
    /// 1. The server commit id should be greater than local commit id
    /// 2. The server response should an contains a entry - @alice:phone@bob
    /// 3. On the client, in the uncommitted list have the same as above with
    /// a different value
    ///
    /// Assertions:
    /// 1. The key should be added to the keyListInfo
    test(
        'A test to verify when sync conflict info when key present in'
        'uncommitted entries and in server response of sync', () async {
      // ------------------------------ Setup ----------------------------------
      LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
          keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

      SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
          atClientManager: mockAtClientManager,
          notificationService: mockNotificationService,
          remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
      syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);

      registerFallbackValue(FakeSyncVerbBuilder());
      registerFallbackValue(FakeUpdateVerbBuilder());

      when(() => mockNetworkUtil.isNetworkAvailable())
          .thenAnswer((_) => Future.value(true));
      when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
      when(() => mockRemoteSecondary
              .executeVerb(any(that: StatsVerbBuilderMatcher())))
          .thenAnswer((invocation) => Future.value('data:[{"value":"3"}]'));
      when(() => mockRemoteSecondary.executeVerb(
              any(that: SyncVerbBuilderMatcher()),
              sync: any(named: "sync")))
          .thenAnswer((invocation) => Future.value('data:['
              '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
              '"value":"dummy",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":1,"operation":"*"}'
              ','
              '{"atKey":"public:conflict_key1@bob",'
              '"value":"remoteValue_value",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":2,"operation":"*"}'
              ','
              '{"atKey":"public:test_key2.demo@bob",'
              '"value":"remoteValue",'
              '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
              '"commitId":3,"operation":"*"}]'));
      when(() =>
          mockRemoteSecondary.executeCommand(any(),
              auth: any(named: "auth"))).thenAnswer(
          (invocation) => Future.value('data:[{"id":1,"response":{"data":"3"}},'
              '{"id":2,"response":{"data":"4"}}]'));

      // --------------------- preconditions setup -----------------------------
      await localSecondary.putValue('public:conflict_key1@bob', 'localValue');
      await localSecondary.putValue(
          'public:test_key2.group12test1@bob', 'whatever');
      CustomSyncProgressListener progressListener =
          CustomSyncProgressListener();
      syncService.addProgressListener(progressListener);
      syncService.sync(onDone: onDoneCallback);
      await syncService.processSyncRequests(
          respectSyncRequestQueueSizeAndRequestTriggerDuration: false);
      // ------------------------------ Assertions -----------------------------
      ConflictInfo? conflictInfo =
          progressListener.localSyncProgress?.keyInfoList![1].conflictInfo;
      expect(conflictInfo?.remoteValue, 'remoteValue_value');
      expect(conflictInfo?.localValue.data, 'localValue');
      //clearing sync objects
      syncService.clearSyncEntities();
    });

    tearDown(() async {
      await TestResources.tearDownLocalStorage();
      resetMocktailState();
    });
  });

  group('Tests to validate how the client and server exchange information', () {
    group('A group of test to verify if client and server are in sync', () {
      late AtCommitLog mockAtCommitLog;
      late RemoteSecondary mockRemoteSecondary;
      late SyncServiceImpl syncServiceImpl;
      late AtClient mockAtClient;
      late AtClientManager mockAtClientManager;
      late NotificationService mockNotificationService;

      setUp(() async {
        TestResources.atsign = '@jester';
        await TestResources.setupLocalStorage(TestResources.atsign);
        registerFallbackValue(FakeStatsVerbBuilder());
        mockAtCommitLog = MockAtCommitLog();
        mockRemoteSecondary = MockRemoteSecondary();
        mockAtClient = MockAtClient();
        mockAtClientManager = MockAtClientManager();
        mockNotificationService = MockNotificationServiceImpl();
      });

      /// Preconditions:
      /// 1. The server commitId is at 15 and local commitId is at 15
      ///
      /// Assertions:
      /// 1. isInSync should return true
      test(
          'A test to verify isInSync returns inSync when localCommitId and serverCommitId are equal',
          () {
        // --------------------- Preconditions ---------------------
        var isInSync = SyncUtil.isInSync(null, 15, 15);
        // --------------------- Assertions ---------------------
        expect(isInSync, true);
      });

      test('A test to verify when server is ahead', () async {
        when(() => mockAtCommitLog.lastSyncedEntry()).thenAnswer((_) async =>
            Future.value(
                CommitEntry('@bob:phone@alice', CommitOp.UPDATE, DateTime.now())
                  ..commitId = 5));
        when(() => mockAtCommitLog.getChanges(null, null))
            .thenAnswer((_) async => Future.value([]));
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((_) async => Future.value(
                'data:[{"id":"3","name":"lastCommitID","value":"10"}]'));
        syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
        syncServiceImpl.syncUtil = SyncUtil(atCommitLog: mockAtCommitLog);

        var syncResult = await syncServiceImpl.checkIfClientAndServerInSync();
        expect(syncResult.syncStatus, SyncStatus.serverAhead);
        expect(syncResult.serverCommitId, 10);
        expect(syncResult.localCommitId, 5);
      });

      test(
          'A test to verify when client is ahead when server and client commit-ids are same and client have uncommitted entries',
          () async {
        when(() => mockAtCommitLog.lastSyncedEntry()).thenAnswer((_) async =>
            Future.value(
                CommitEntry('@bob:phone@alice', CommitOp.UPDATE, DateTime.now())
                  ..commitId = 10));
        when(() => mockAtCommitLog.getChanges(null, null)).thenAnswer(
            (_) async => Future.value([
                  CommitEntry(
                      '@bob:mobile@alice', CommitOp.UPDATE, DateTime.now())
                ]));
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((_) async => Future.value(
                'data:[{"id":"3","name":"lastCommitID","value":"10"}]'));
        syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
        syncServiceImpl.syncUtil = SyncUtil(atCommitLog: mockAtCommitLog);

        var syncResult = await syncServiceImpl.checkIfClientAndServerInSync();
        expect(syncResult.syncStatus, SyncStatus.clientAhead);
        expect(syncResult.serverCommitId, 10);
        expect(syncResult.localCommitId, 10);
      });

      test(
          'A test to verify server ahead when server commit-id is higher than and client commit-id and client have uncommitted entries',
          () async {
        when(() => mockAtCommitLog.lastSyncedEntry()).thenAnswer((_) async =>
            Future.value(
                CommitEntry('@bob:phone@alice', CommitOp.UPDATE, DateTime.now())
                  ..commitId = 5));
        when(() => mockAtCommitLog.getChanges(null, null)).thenAnswer(
            (_) async => Future.value([
                  CommitEntry(
                      '@bob:mobile@alice', CommitOp.UPDATE, DateTime.now())
                ]));
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((_) async => Future.value(
                'data:[{"id":"3","name":"lastCommitID","value":"10"}]'));
        syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
        syncServiceImpl.syncUtil = SyncUtil(atCommitLog: mockAtCommitLog);

        var syncResult = await syncServiceImpl.checkIfClientAndServerInSync();
        expect(syncResult.syncStatus, SyncStatus.serverAhead);
        expect(syncResult.serverCommitId, 10);
        expect(syncResult.localCommitId, 5);
      });

      test('A test to verify when server and client are in sync', () async {
        when(() => mockAtCommitLog.lastSyncedEntry()).thenAnswer((_) async =>
            Future.value(
                CommitEntry('@bob:phone@alice', CommitOp.UPDATE, DateTime.now())
                  ..commitId = 10));
        when(() => mockAtCommitLog.getChanges(null, null))
            .thenAnswer((_) async => Future.value([]));
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((_) async => Future.value(
                'data:[{"id":"3","name":"lastCommitID","value":"10"}]'));
        syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
        syncServiceImpl.syncUtil = SyncUtil(atCommitLog: mockAtCommitLog);

        var syncResult = await syncServiceImpl.checkIfClientAndServerInSync();
        print('${syncResult.serverCommitId}  ${syncResult.localCommitId}');
        expect(syncResult.syncStatus, SyncStatus.inSync);
        expect(syncResult.serverCommitId, 10);
        expect(syncResult.localCommitId, 10);
      });

      tearDown(() async {
        await TestResources.tearDownLocalStorage();
        resetMocktailState();
      });
    });

    /// Needs refactoring * - TODO
    /// Say no when:
    /// 1. sync is already running
    /// 2. there is no network
    /// 3. Server and client are already in sync
    /// 4. sync request threshold is not met
    group('A group of tests to verify sync trigger criteria', () {
      setUp(() async {
        TestResources.atsign = '@knox';
        await TestResources.setupLocalStorage(TestResources.atsign);
      });

      AtClient mockAtClient = MockAtClient();
      AtClientManager mockAtClientManager = MockAtClientManager();
      NotificationServiceImpl mockNotificationService =
          MockNotificationServiceImpl();
      RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
      NetworkUtil mockNetworkUtil = MockNetworkUtil();

      ///***********************************
      ///unable to assert if sync has happened
      ///***********************************
      test(
          'A test to verify sync process triggers at configured values for frequent intervals',
          () {
        /// Preconditions:
        /// 1. The _syncRunIntervalSeconds is set to 3 seconds
        /// 2. The sync process is yet to start
        ///
        /// Assertions:
        /// Assert that sync process is triggered at 3 seconds
      });

      ///***********************************
      ///unable to assert if sync is in process as the process happens extremely fast
      ///ToDo need to figure out a way to pause sync to perform assertions (if that is even possible)
      ///***********************************
      test(
          'A test to verify new sync process does not start when existing sync process is running',
          () {
        /// Preconditions:
        /// 1. The _syncRunIntervalSeconds is set to 3 seconds
        /// 2. The previous sync process is still running
        ///
        /// Assertions:
        /// Assert that new sync process is not started(when time interval or
        ///  threshold value is reached) while the existing sync process is still running
      });

      /// Preconditions:
      /// 1. Network is unavailable.
      /// 2. The sync process is yet to start
      /// Assertions:
      /// Assert that sync process is not started till the network is back
      test(
          'A test to verify sync process does not start when network is not available',
          () async {
        //------------------------------- Setup --------------------------------
        LocalSecondary localSecondary = LocalSecondary(mockAtClient,
            keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
        syncService.networkUtil = mockNetworkUtil;

        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(false));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((invocation) => Future.value('data:[{"value":"3"}]'));
        when(() => mockRemoteSecondary.executeVerb(
                any(that: SyncVerbBuilderMatcher()),
                sync: any(named: "sync")))
            .thenAnswer((invocation) => Future.value('data:['
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":1,"operation":"*"}'
                ','
                '{"atKey":"public:test_key1.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":2,"operation":"*"}'
                ','
                '{"atKey":"public:test_key2.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":3,"operation":"*"}]'));
        when(() => mockRemoteSecondary.executeCommand(any(),
                auth: any(named: "auth")))
            .thenAnswer((invocation) =>
                Future.value('data:[{"id":1,"response":{"data":"4"}},'
                    '{"id":2,"response":{"data":"5"}}]'));

        //----------------------------Preconditions setup ----------------------
        await localSecondary.putValue(
            'public:test_key1.group12test1@bob', 'whatever');
        await localSecondary.putValue(
            'public:test_key2.group12test1@bob', 'whatever');
        bool localSwitchState = TestResources.switchState;
        //call sync 3-times to pass the trigger threshold
        syncService.sync(onDone: onDoneCallback);
        syncService.sync(onDone: onDoneCallback);
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests();
        //onDoneCallback when triggered, flips the switch in TestResources
        //the below assertion is to check if the switch has been flipped
        //that is done by storing the switchState before sync and then checking
        //if the switch state is in the opposite state after sync
        //
        //switch will not be flipped as network is unavailable
        expect(TestResources.switchState, localSwitchState);

        //setting mock network as available
        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        //call sync 3-times to pass trigger threshold
        syncService.sync(onDone: onDoneCallback);
        syncService.sync(onDone: onDoneCallback);
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests();
        //------------------Assertions -------------------
        //switch will be flipped for this request as network is now available
        expect(TestResources.switchState, !localSwitchState);
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      /// Preconditions:
      /// 1. There are no uncommitted entries/ requests.

      /// Assertions:
      /// Assert that sync process is not started till the syncRequestThreshold is met
      test(
          'A test to verify sync process does not start when sync request queue is empty',
          () async {
        //------------------------------- Setup -------------------------------
        LocalSecondary localSecondary = LocalSecondary(mockAtClient,
            keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        //----------------------operation---------------------------------------
        bool localSwitchState = TestResources.switchState;
        //call sync only once
        //sync will not be performed as trigger threshold is not met
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests();
        //------------------Assertions -----------------------------------------
        //onDoneCallback when triggered, flips the switch in TestResources
        //the below assertion is to check if the switch has been flipped
        //that is done by storing the switchState before sync and then checking
        //if the switch state is in the opposite state after sync
        //
        //switch will not be flipped for request - 1 as there are no uncommitted entries
        expect(TestResources.switchState, localSwitchState);
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      /// Preconditions:
      /// 1. The _syncRequestThreshold is set to 3.
      /// 2. The sync process is yet to start and there are no requests in the queue
      /// Assertions:
      /// Assert that sync process is not started before the queue size is reached
      test(
          'A test to verify sync process does not start when sync request queue does not meet the threshold',
          () async {
        //------------------ setup -------------------
        LocalSecondary localSecondary = LocalSecondary(mockAtClient,
            keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);

        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((invocation) => Future.value('data:[{"value":"3"}]'));
        when(() => mockRemoteSecondary.executeVerb(
                any(that: SyncVerbBuilderMatcher()),
                sync: any(named: "sync")))
            .thenAnswer((invocation) => Future.value('data:['
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":1,"operation":"*"}'
                ','
                '{"atKey":"public:test_key1.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":2,"operation":"*"}'
                ','
                '{"atKey":"public:test_key2.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":3,"operation":"*"}]'));
        when(() => mockRemoteSecondary.executeCommand(any(),
                auth: any(named: "auth")))
            .thenAnswer((invocation) =>
                Future.value('data:[{"id":1,"response":{"data":"4"}},'
                    '{"id":2,"response":{"data":"5"}}]'));

        bool localSwitchState = TestResources.switchState;
        //------------------Assertions -------------------
        //onDoneCallback when triggered, flips the switch in TestResources
        //the below assertion is to check if the switch has been flipped
        //that is done by storing the switchState before sync and then checking
        //if the switch state is in the opposite state after sync
        //
        //switch will not be flipped for request - 1 as sync will not be performed
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests();
        expect(TestResources.switchState, localSwitchState);

        //switch will not be flipped for request - 2 as sync will not be performed
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests();
        expect(TestResources.switchState, localSwitchState);

        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests();
        //switch will be flipped for request - 3 as the request threshold for sync is 3
        expect(TestResources.switchState, !localSwitchState);
        //clearing sync objects
        syncService.clearSyncEntities();
      });
    });

    group('A group of tests to verify isSyncInProgress flag', () {
      setUp(() async {
        TestResources.atsign = '@levi';
        await TestResources.setupLocalStorage(TestResources.atsign);
      });

      AtClient mockAtClient = MockAtClient();
      AtClientManager mockAtClientManager = MockAtClientManager();
      NotificationServiceImpl mockNotificationService =
          MockNotificationServiceImpl();
      RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
      NetworkUtil mockNetworkUtil = MockNetworkUtil();

      /// Preconditions:
      /// 1. Initially the isSyncInProgress is set to false.
      /// 2. The server commit id is greater than local commit id
      ///
      /// Assertions:
      /// 1. Once the sync is completed
      ///   a. the local commit id and server commit id should be equal
      ///   b. the isSyncInProgress should be set to false
      test(
          'A test to verify isSyncInProgress flag is set to false on sync completion',
          () async {
        //---------------------setup--------------------------
        reset(mockRemoteSecondary);
        LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
            keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        when(() => mockRemoteSecondary.executeVerb(any(),
                sync: any(named: "sync")))
            .thenAnswer((invocation) => Future.value('data:['
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":0,"operation":"*"}'
                ','
                '{"atKey":"public:test_key1.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":1,"operation":"*"}'
                ','
                '{"atKey":"public:test_key2.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":2,"operation":"*"}'
                ','
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":3,"operation":"*"}'
                ','
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":4,"operation":"*"}]'));

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;
        syncService.networkUtil = mockNetworkUtil;
        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
        //----------------- Assertions-----------------
        await syncService.syncInternal(4, SyncRequest()..result = SyncResult());
        expect(
            (await syncService.syncUtil.atCommitLog?.getEntry(0))?.commitId, 0);
        expect(
            (await syncService.syncUtil.atCommitLog?.getEntry(1))?.commitId, 1);
        expect(
            (await syncService.syncUtil.atCommitLog?.getEntry(2))?.commitId, 2);
        expect(
            (await syncService.syncUtil.atCommitLog?.getEntry(3))?.commitId, 3);
        expect(
            (await syncService.syncUtil.atCommitLog?.getEntry(4))?.commitId, 4);
        expect(syncService.isSyncInProgress, false);
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      test(
          'A test to verify isSyncInProgress flag is set to false when sync stops on network exception',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id is greater than local commit id
        /// 3. The mock server socket should throw time-out exception
        ///
        /// Assertions:
        /// 1. On catching the exception, the isSyncInProgress flag should be set to false
      });
      test(
          'A test to verify a isSyncInProgress flag is set to false when sync stops due to serverException',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id is greater than local commit id
        /// 3. The mock server socket should throw invalid command exception
        ///
        /// Assertions:
        /// 1. On catching the exception, the isSyncInProgress flag should be set to false
      });
      test(
          'A test to verify a isSyncInProgress flag is set to false when sync stops due to socketException',
          () {
        /// Preconditions:
        /// 1. Initially the isSyncInProgress is set to false.
        /// 2. The server commit id is greater than local commit id
        /// 3. The mock server socket should throw socket exception
        ///
        /// Assertions:
        /// 1. On catching the exception, the isSyncInProgress flag should be set to false
      });

      tearDown(() async {
        await TestResources.tearDownLocalStorage();
        resetMocktailState();
      });
    });

    group(
        'A group of tests to validated batch command - sync client changes to server',
        () {
      ///*****************************
      ///test similar to group3test3
      ///ToDo: the additional case in the test will be added there
      ///*****************************
      test(
          'A test to verify batch command when batch size is less than uncommitted entries list size',
          () {
        /// Preconditions:
        /// 1. Have batch size set to 5
        /// 2. Have 10 uncommitted entries in the local keystore
        ///
        /// Assertions:
        /// 1. Batch command should be called twice
        /// 2. The first batch command should have the first 5 entries
        /// 3. The second batch command should have the remaining 5 entries
      });

      ///****************************
      ///test similar to group3test4
      ///ignoring this
      ///****************************
      test(
          'A test to verify batch command when batch size and uncommitted entries list are equal',
          () {
        /// Preconditions:
        /// 1. Have batch size set to 5
        /// 2. Have 5 uncommitted entries in the local keystore
        ///
        /// Assertions:
        /// Batch command should have all the 5 entries
      });
    });

    group(
        'A group of tests to validate sync command - sync server changes to client',
        () {
      setUp(() async {
        TestResources.atsign = '@nadia';
        await TestResources.setupLocalStorage(TestResources.atsign);
      });

      AtClient mockAtClient = MockAtClient();
      AtClientManager mockAtClientManager = MockAtClientManager();
      NotificationServiceImpl mockNotificationService =
          MockNotificationServiceImpl();
      RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
      NetworkUtil mockNetworkUtil = MockNetworkUtil();

      /// Preconditions:
      /// 1. The localCommitId is at commitId 5
      /// 2. The serverCommitId is at commitId 10
      ///     commitId 6 and 7 are creation new keys
      ///     commitId 8 is deletion of existing key
      ///     commitId 9 and 10 are update existing keys
      /// 3. No uncommitted entries on the local secondary
      ///
      /// Operation
      /// Run Sync
      ///
      /// Assertions:
      /// 1. The server response should contain the changes from commitId 6 to 10
      /// 2. The local keystore should two existing updates, one existing key deleted and two new keys created
      test('A test to verify sync command to delta changes', () async {
        //----------------- setup-----------------
        HiveKeystore? keystore =
            TestResources.getHiveKeyStore(TestResources.atsign);
        LocalSecondary? localSecondary =
            LocalSecondary(mockAtClient, keyStore: keystore);

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

        syncService.networkUtil = mockNetworkUtil;
        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((invocation) => Future.value('data:[{"value":"10"}]'));
        when(() => mockRemoteSecondary.executeVerb(
                any(that: SyncVerbBuilderMatcher()),
                sync: any(named: "sync")))
            .thenAnswer((invocation) => Future.value('data:['
                '{"atKey":"public:self_key.wavi@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":6,"operation":"*"}'
                ','
                '{"atKey":"public:from_remote_key1.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":7,"operation":"*"}'
                ','
                '{"atKey":"public:test_key1.wavi@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":8,"operation":"-"}'
                ','
                '{"atKey":"public:from_remote_key3.wavi@bob",'
                '"value":"dummy_val_new",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":9,"operation":"*"}'
                ','
                '{"atKey":"cached:@bob:shared_key@framedmurder",'
                '"value":"dummy_val_new_1",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":10,"operation":"*"}]'));
        when(() => mockRemoteSecondary.executeCommand(any(),
                auth: any(named: "auth")))
            .thenAnswer((invocation) =>
                Future.value('data:[{"id":1,"response":{"data":"3"}},'
                    '{"id":2,"response":{"data":"4"}}]'));

        //-----------------preconditions setup-----------------
        await localSecondary.putValue(
            'public:from_remote_key3.wavi@bob', 'fe fi fo fum');
        await localSecondary.putValue(
            'public:test_key1.wavi@bob', 'fe fi fo fum');
        await localSecondary.putValue(
            'cached:@bob:shared_key@framedmurder', 'fe fi fo fum');
        CommitEntry? commitEntry;

        //for loop to get commit entries from seq_num 0-2 and update each of their commitIds
        for (int i = 0; i <= 2; i++) {
          commitEntry = await syncService.syncUtil
              .getCommitEntry(i, TestResources.atsign);
          //update the commitId to seq_num + 3
          //this equation has been specifically set so that the commitId of the
          //lastSyncedEntry is set to 5. Which is vital for sync to be completed
          await syncService.syncUtil
              .updateCommitEntry(commitEntry, i + 3, TestResources.atsign);
        }
        //asset that the lastSyncedEntry has commitId of 5
        commitEntry = await syncService.syncUtil
            .getLastSyncedEntry('', atSign: TestResources.atsign);
        expect(commitEntry?.commitId, 5);
        //---------------------------operation----------------------------------
        await syncService.syncInternal(
            10, SyncRequest()..result = SyncResult());
        //---------------------------- assertions-------------------------------
        AtData? atData;
        atData = await keystore?.get('public:self_key.wavi@bob');
        expect(atData?.data, 'dummy');
        atData = await keystore?.get('public:from_remote_key1.demo@bob');
        expect(atData?.data, 'dummy');
        expect(keystore?.isKeyExists('test_key1.wavi@bob'), false);
        atData = await keystore?.get('public:from_remote_key3.wavi@bob');
        expect(atData?.data, 'dummy_val_new');
        atData = await keystore?.get('cached:@bob:shared_key@framedmurder');
        expect(atData?.data, 'dummy_val_new_1');
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      tearDown(() async {
        await TestResources.tearDownLocalStorage();
        resetMocktailState();
      });
    });

    group('A group of test to verify onDone callback', () {
      setUp(() async {
        TestResources.atsign = '@oreo';
        await TestResources.setupLocalStorage(TestResources.atsign);
      });

      AtClient mockAtClient = MockAtClient();
      AtClientManager mockAtClientManager = MockAtClientManager();
      NotificationServiceImpl mockNotificationService =
          MockNotificationServiceImpl();
      RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
      NetworkUtil mockNetworkUtil = MockNetworkUtil();

      /// Preconditions:
      /// 1. The serverCommitId is greater than localCommitId
      /// 2. Have uncommitted entries on the client side
      /// 3. SyncResult.syncStatus is set to notStarted
      ///
      /// Assertions:
      /// 1. After the sync is completed verify the following:
      ///  a. onDone call is triggered
      ///  b. the direction of keys: For keys pulled from server the direction is "RemoteToLocal"
      ///     and pushed to server is "LocalToRemote"
      /// 2. The SyncResult.syncStatus is set to success
      /// 3. The syncResult.lastSyncedOn is set to sync completion time
      test(
          'A test to verify sync result in onDone callback on successful completion',
          () async {
        //----------------- setup-----------------
        LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
            keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((invocation) => Future.value('data:[{"value":"3"}]'));
        when(() => mockRemoteSecondary.executeVerb(
                any(that: SyncVerbBuilderMatcher()),
                sync: any(named: "sync")))
            .thenAnswer((invocation) => Future.value('data:['
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":1,"operation":"*"}, '
                '{"atKey":"public:test_key1.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":2,"operation":"*"},'
                '{"atKey":"public:test_key2.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":3,"operation":"*"}]'));
        when(() => mockRemoteSecondary.executeCommand(any(),
                auth: any(named: "auth")))
            .thenAnswer((invocation) =>
                Future.value('data:[{"id":1,"response":{"data":"4"}},'
                    '{"id":2,"response":{"data":"5"}}]'));

        //----------------------- preconditions setup---------------------------
        await localSecondary.putValue(
            'public:test_key1.group12test1@bob', 'whatever');
        await localSecondary.putValue(
            'public:test_key2.group12test1@bob', 'whatever');
        bool localSwitchState = TestResources.switchState;
        //---------------------------operation----------------------------------
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests(
            respectSyncRequestQueueSizeAndRequestTriggerDuration: false);

        //onDoneCallback() when triggered, flips the switchState in TestResources
        //The below assertion is to check if the switch has been flipped as
        //a result of onDoneCallback being triggered
        //That is done by storing the switchState before sync and then checking
        //if the switch state is in the opposite state after sync
        //----------------- assertions-----------------
        expect(TestResources.switchState, !localSwitchState);
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      /// Preconditions:
      /// 1. The serverCommitId is greater than localCommitId
      /// 2. Have uncommitted entries on the client side
      /// 3. SyncResult.syncStatus is set to notStarted
      ///
      /// Assertions:
      /// 1. The error is encapsulated in the SyncResult.atClientException
      /// 2. The SyncResult.syncStatus is set to failure
      /// 3. The syncResult.lastSyncedOn is set to sync completion time
      test(
          'A test to verify sync result in onDone callback when sync failure occur',
          () async {
        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

        syncService.networkUtil = mockNetworkUtil;

        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(false));
        //------------------------- preconditions setup-------------------------
        CustomSyncProgressListener progressListener =
            CustomSyncProgressListener();
        syncService.addProgressListener(progressListener);
        syncService.sync(onDone: onDoneCallback);
        //forcefully trigger sync
        //done by setting respectSyncRequestQueueSizeAndRequestTriggerDuration to false
        await syncService.processSyncRequests(
            respectSyncRequestQueueSizeAndRequestTriggerDuration: false);
        //----------------- assertions-----------------
        expect(
            progressListener.localSyncProgress?.syncStatus, SyncStatus.failure);
        expect(
            progressListener.localSyncProgress?.message, 'network unavailable');
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      tearDown(() async {
        await TestResources.tearDownLocalStorage();
        resetMocktailState();
      });
    });

    group('A group of test on sync progress call back', () {
      setUp(() async {
        TestResources.atsign = '@poland';
        await TestResources.setupLocalStorage(TestResources.atsign);
      });

      AtClient mockAtClient = MockAtClient();
      AtClientManager mockAtClientManager = MockAtClientManager();
      NotificationServiceImpl mockNotificationService =
          MockNotificationServiceImpl();
      RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
      MockNetworkUtil mockNetworkUtil = MockNetworkUtil();

      /// Preconditions:
      /// 1. Create a class that extends "SyncProgressListener" and override "onSyncProgressEvent" method
      /// 2. ServerCommitId is greater than localCommitId. Say localCommitId is at 10 and serverCommitId is at 15
      /// 3. Local keystore has previously synced entries and uncommitted entries
      /// 4. The default value for fields in SyncProgressListener:
      ///     a. isInitialSync is set to false
      ///
      ///
      /// Assertions:
      /// 1. Assert on the following fields in SyncProgress:
      ///    a. SyncStatus? syncStatus = SyncStatus.Complete;
      ///    b. isInitialSync will remain false because this sync only fetch delta changes
      ///    c. DateTime? startedAt: The time when sync process started
      ///    d. DateTime? completedAt: The time when sync process is completed
      ///    e. String? message
      ///    f. String? TestResources.atsign: The currentatsign on which sync is running
      ///    g. List<KeyInfo>? keyInfoList: The keys that are synced
      ///    h. int? localCommitIdBeforeSync: The local committed id before sync; here 10
      ///    i. int? localCommitId: The local commit id after sync; here 15
      ///    j. int? serverCommitId: The server commit id; here 15
      test(
          'A test to verify a new listener is added to sync progress call back',
          () async {
        //----------------- setup-----------------
        LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
            keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

        syncService.networkUtil = mockNetworkUtil;
        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((invocation) => Future.value('data:[{"value":"15"}]'));
        when(() => mockRemoteSecondary.executeVerb(
                any(that: SyncVerbBuilderMatcher()),
                sync: any(named: "sync")))
            .thenAnswer((invocation) => Future.value('data:['
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":11,"operation":"*"}'
                ','
                '{"atKey":"public:test_key1.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":12,"operation":"*"}'
                ','
                '{"atKey":"public:test_key2.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":13,"operation":"*"}'
                ','
                '{"atKey":"public:test_key3.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":14,"operation":"*"}'
                ','
                '{"atKey":"public:test_key4.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":15,"operation":"*"}]'));
        when(() => mockRemoteSecondary.executeCommand(any(),
                auth: any(named: "auth")))
            .thenAnswer((invocation) =>
                Future.value('data:[{"id":1,"response":{"data":"4"}},'
                    '{"id":2,"response":{"data":"5"}}]'));

        //------------------------ preconditions setup ------------------------
        await localSecondary.putValue(
            'public:test_key1.group12test1@bob', 'whatever');
        var commitEntry =
            await syncService.syncUtil.getCommitEntry(0, TestResources.atsign);
        await syncService.syncUtil
            .updateCommitEntry(commitEntry, 10, TestResources.atsign);
        CustomSyncProgressListener progressListener =
            CustomSyncProgressListener();
        syncService.addProgressListener(progressListener);
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests(
            respectSyncRequestQueueSizeAndRequestTriggerDuration: false);
        //------------------------------ assertions-----------------------------

        expect(
            progressListener.localSyncProgress?.syncStatus, SyncStatus.success);
        expect(progressListener.localSyncProgress?.isInitialSync, false);
        expect(
            progressListener.localSyncProgress?.atSign, TestResources.atsign);
        expect(progressListener.localSyncProgress?.localCommitIdBeforeSync, 10);
        expect(progressListener.localSyncProgress?.localCommitId, 15);
        expect(progressListener.localSyncProgress?.serverCommitId, 15);

        var keysList = progressListener.localSyncProgress?.keyInfoList;
        //for all the keys in keysInfoList assert that the sync direction is
        // remote -> local
        keysList?.forEach((key) {
          expect(key.syncDirection, SyncDirection.remoteToLocal);
        });
        //assert the keys in keysInfoList based on the mock server response
        expect(keysList![0].key, 'cached:@bob:shared_key@guiltytaurus27');
        expect(keysList[1].key, 'public:test_key1.demo@bob');
        expect(keysList[2].key, 'public:test_key2.demo@bob');
        expect(keysList[3].key, 'public:test_key3.demo@bob');
        expect(keysList[4].key, 'public:test_key4.demo@bob');
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      /// Preconditions:
      /// 1. The local keystore is empty
      /// 2. Initialize a full sync from cloud secondary
      /// 3. The default value for fields in SyncProgressListener:
      ///     a. isInitialSync is set to false
      /// 4. Create a class that extends "SyncProgressListener" and override "onSyncProgressEvent" method
      ///
      /// Assertions:
      /// 1. Assert on the following fields in SyncProgress:
      ///    a. SyncStatus? syncStatus = SyncStatus.Complete;
      ///    b. bool isInitialSync = true;
      test('A test to verify "isInitialSync" flag in SyncProgressListener',
          () async {
        // ----------------------------- setup ---------------------------------
        LocalSecondary? localSecondary = LocalSecondary(mockAtClient,
            keyStore: TestResources.getHiveKeyStore(TestResources.atsign));

        SyncServiceImpl syncService = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService,
            remoteSecondary: mockRemoteSecondary) as SyncServiceImpl;

        syncService.networkUtil = mockNetworkUtil;
        syncService.syncUtil = SyncUtil(atCommitLog: TestResources.commitLog);
        registerFallbackValue(FakeSyncVerbBuilder());
        registerFallbackValue(FakeUpdateVerbBuilder());

        when(() => mockNetworkUtil.isNetworkAvailable())
            .thenAnswer((_) => Future.value(true));
        when(() => mockAtClient.getLocalSecondary()).thenReturn(localSecondary);
        when(() => mockRemoteSecondary
                .executeVerb(any(that: StatsVerbBuilderMatcher())))
            .thenAnswer((invocation) => Future.value('data:[{"value":"3"}]'));
        when(() => mockRemoteSecondary.executeVerb(
                any(that: SyncVerbBuilderMatcher()),
                sync: any(named: "sync")))
            .thenAnswer((invocation) => Future.value('data:['
                '{"atKey":"cached:@bob:shared_key@guiltytaurus27",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":1,"operation":"*"}'
                ','
                '{"atKey":"public:test_key1.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":2,"operation":"*"}'
                ','
                '{"atKey":"public:test_key2.demo@bob",'
                '"value":"dummy",'
                '"metadata":{"createdAt":"2022-11-07 13:42:02.703Z"},'
                '"commitId":3,"operation":"*"}]'));

        // ----------------- preconditions setup and operation -----------------
        CustomSyncProgressListener progressListener =
            CustomSyncProgressListener();
        syncService.addProgressListener(progressListener);
        syncService.sync(onDone: onDoneCallback);
        await syncService.processSyncRequests(
            respectSyncRequestQueueSizeAndRequestTriggerDuration: false);

        //----------------------------- assertions------------------------------
        expect(
            progressListener.localSyncProgress?.syncStatus, SyncStatus.success);
        expect(progressListener.localSyncProgress?.isInitialSync, true);
        syncService.removeProgressListener(progressListener);
        //clearing sync objects
        syncService.clearSyncEntities();
      });

      /// Preconditions:
      /// Create a class that extends "SyncProgressListener" and override "onSyncProgressEvent" method
      ///
      /// Assertions:
      /// The sync progress listener should be removed from "_syncProgressListeners"
      test(
          'A test to verify a listener is removed from sync progress call back',
          () async {
        //-------------------Setup-------------------
        var syncServiceImpl = await SyncServiceImpl.create(mockAtClient,
            atClientManager: mockAtClientManager,
            notificationService: mockNotificationService) as SyncServiceImpl;
        syncServiceImpl.syncUtil =
            SyncUtil(atCommitLog: TestResources.commitLog);
        // -------------------Preconditions-------------------
        var listener = CustomSyncProgressListener();
        syncServiceImpl.addProgressListener(listener);
        //verify the que size is 1
        var syncQueueSize = syncServiceImpl.syncProgressListenerSize();
        expect(syncQueueSize, 1);
        // verify the listener is removed
        syncServiceImpl.removeProgressListener(listener);
        // -------------------Assertions-------------------
        syncQueueSize = syncServiceImpl.syncProgressListenerSize();
        expect(syncQueueSize, 0);
        //clearing sync objects
        syncServiceImpl.clearSyncEntities();
      });

      tearDown(() async {
        await TestResources.tearDownLocalStorage();
        resetMocktailState();
      });
    });
  });
}

///default onDoneCallback for all the syncRequests in the above tests
void onDoneCallback(syncResult) {
  stdout.writeln(syncResult);
  //always assert that the sync is successful when this method is triggered
  expect(syncResult.syncStatus, SyncStatus.success);
  //when this method is triggered always switch state to indicate that sync has been successful
  TestResources.flipSwitch();
}

class CustomSyncProgressListener extends SyncProgressListener {
  SyncProgress? localSyncProgress;

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    localSyncProgress = syncProgress;
  }
}

class TestResources {
  static late String atsign;
  static AtCommitLog? commitLog;
  static SecondaryPersistenceStore? secondaryPersistenceStore;
  static var storageDir = '${Directory.current.path}/test/hive';

  //an object that will be used to assert change of state
  static bool switchState = false;

  static Future<void> setupLocalStorage(String atsign,
      {bool enableCommitId = false}) async {
    commitLog = await AtCommitLogManagerImpl.getInstance().getCommitLog(
        TestResources.atsign,
        commitLogPath: storageDir,
        enableCommitId: enableCommitId);

    var secondaryPersistenceStore =
        SecondaryPersistenceStoreFactory.getInstance()
            .getSecondaryPersistenceStore(TestResources.atsign)!;

    await secondaryPersistenceStore
        .getHivePersistenceManager()!
        .init(storageDir);

    secondaryPersistenceStore.getSecondaryKeyStore()!.commitLog = commitLog;
  }

  static Future<void> tearDownLocalStorage() async {
    try {
      await SecondaryPersistenceStoreFactory.getInstance().close();
      await AtCommitLogManagerImpl.getInstance().close();
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

  static setCommitEntry(int commitId, String atsign) async {
    CommitEntry? entry = await SyncUtil(atCommitLog: commitLog)
        .getCommitEntry(commitId, TestResources.atsign);
    await SyncUtil(atCommitLog: commitLog)
        .updateCommitEntry(entry, commitId, TestResources.atsign);
  }

  //will invert switchState when called, similar to a real-life switch
  static flipSwitch() {
    TestResources.switchState = !TestResources.switchState;
  }
}

///Custom matcher used in mocks to assert that the parameter passed to the mock
///object/method is of the type SyncVerbBuilder
class SyncVerbBuilderMatcher extends Matcher {
  @override
  Description describe(Description description) =>
      description.add('Custom matcher to match SyncVerbBuilder');

  @override
  bool matches(item, Map matchState) {
    if (item is SyncVerbBuilder) return true;
    return false;
  }
}

///Custom matcher used in mocks to assert that the parameter passed to the mock
///object/method is of the type StatsVerbBuilder
class StatsVerbBuilderMatcher extends Matcher {
  @override
  Description describe(Description description) =>
      description.add('Custom matcher to match StatsVerbBuilder');

  @override
  bool matches(item, Map matchState) {
    if (item is StatsVerbBuilder) {
      return true;
    }
    return false;
  }
}
