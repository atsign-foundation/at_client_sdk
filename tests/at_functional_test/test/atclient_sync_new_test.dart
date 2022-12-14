import 'package:test/test.dart';

void main() {
  group(
      'Tests to validate how items are added to the uncommitted queue on the client side (upon data store operations)',
      () {
    test(
        'Verify uncommitted queue on creation,updation,deletion of a public key',
        () {
      /// Preconditions:
      /// 1. key should not aready exist in the lcoal

      /// Operation:
      /// 1. Create a public key locally
      /// 2. Update the same key locally with a new value
      /// 3. Delete the same key locally

      /// Assertions-1:
      /// 1. The key should be synced to the cloud secondary
      /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
      /// DateTime which is less than DateTime.now()
      /// Assertions-2:
      /// 1. The new value should be synced to the cloud secondary
      /// 2. Assert the metadata of the key. "UpdatedAt" should be populated with
      /// DateTime which is less than DateTime.now()
      /// Assertions-3:
      /// 1. The key should be deleted from the cloud secondary
      /// 2. Assert that key does not exist in the cloud
    });

    test(
        'Verify uncommitted queue on creation,updation,deletion of a shared key',
        () {
      /// Preconditions:
      /// 1. The key should not exist in the local
     
      /// Operation:
      /// 1. Create a shared key locally
      /// 2. Update the same key locally with a new value
      /// 3. Delete the same key locally

      /// Assertions-1:
      /// 1. The key should be synced to the cloud secondary and key should nbe available in
      /// shared with's secondary
      /// 2. Assert the metadata of the key. "CreatedAt" should be populated with
      /// DateTime which is less than DateTime.now()
      /// Assertions-2:
      /// 1. The new value should be synced to the cloud secondary
      /// 2. Assert the metadata of the key. "UpdatedAt" should be populated with
      /// DateTime which is less than DateTime.now()
      /// Assertions-3:
      /// 1. The key should be deleted from the cloud secondary
      /// 2. Assert that key does not exist in the cloud
    });

    test(
        'Verify uncommitted queue on creation,updation,deletion of a local key',
        () {
      /// Preconditions:
      /// 1. There should be no entry for the same key in the key store
      /// 2. There should be no entry for the same key in the commit log

      /// Operation:
      /// 1. Create a local key locally
      /// 2. Update the same key locally with a new value
      /// 3. Delete the same key locally

      /// Assertions-1:
      /// 1. The key should not be synced to the cloud secondary
      /// 2. Assert that the key does not exist in the cloud
      /// Assertions-2:
      /// 1. The new value should not be synced to the cloud secondary
      /// 2. Assert that the key does not exist in the cloud
      /// Assertions-3:
      /// 1. The key should not be synced to the cloud secondary
      /// 2. Assert that key does not exist in the cloud
    });
  });

  group('tests related to TTL and TTB', () {
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

    test('A test to verify when a key is set with TTB and key is available',
        () {
      /// Preconditions:
      /// 1. There should be no entry for the same key in the key store
      /// 2. There should be no entry for the same key in the commit log

      /// Operation:
      /// Put a key with TTB say 30 seconds

      /// Assertions:
      /// 1. Assert that the value is returned only after 30seconds
      /// 2. A metadata "CreatedAt" should be populated with
      /// DateTime which is less than DateTime.now()
    });

    group(
        'Tests to validate how the client processes updates from the server - can the client reject? under what conditions? what happens upon a rejection?',
        () {
      test('Update from server for a key that exists in local secondary', () {
        /// Preconditions:
        /// 1. The key already exists in the local keystore
        /// 2. An entry should already exist in the local commit log
        ///
        /// Operation:
        /// 1. Run sync
        ///
        /// Assertions:
        /// 1. The value and metadata of the existing key should be updated
        ///    Since we are updated existing key "createdAt" field should remain as is and
        ///    "updatedAt" field should be updated.
      });

      test(
          'Update from server for a key that does not exist in local secondary',
          () async {
        /// Preconditions:
        /// 1. The key does not exist in the local keystore
        ///
        /// Operation:
        /// 1. Run sync
        /// Assertions:
        /// 1. The new key should be created in the cloud
        /// 2. An entry created in the commit log with the new commit id
      });

      test('Delete from server for a key that exists in local secondary', () {
        /// Preconditions:
        /// 1. The key already exists in the local keystore
        /// 2. An entry in commitLog with commitOp.Update
        ///
        /// Operation:
        /// 1. Run sync
        ///
        /// Assertions:
        /// 1. The key should be deleted from the cloud
        /// 2. An entry with commitOp.delete should be added to the commit log
      });

      test(
          'Delete from server for a key that does not exist in local secondary',
          () async {
        /// Precondition:
        /// The key does not exist in the local secondary
        ///
        /// Assertions;
        /// An entry should be added to commit log to prevent sync imbalance
      });
    });

    group('A group of test on sync regex', () {
      test('A test to verify that only the keys matching the regex are synced',
          () {
        /// Preconditions:
        /// 1. server and local are in sync
        /// 2. In the local keystore have 5 uncommitted entries with .wavi and .atmosphere
        /// 3. Initiate sync with regex - ".wavi"
        ///
        /// Assertions:
        /// 1. Server and local should be in sync and entries with only .wavi
        ///    must be synced to cloud secondary
      });
    });

    group('A group of test on sync progress call back', () {
      test(
          'A test to verify sync progress when local is ahead of cloud secondary',
          () {
        /// Preconditions:
        /// 1. server is at commitId 10 and local is at commitId 20
        ///
        /// Operation:
        ///  Initiate sync
        ///
        /// Assertions:
        /// 1. sync direction should be SyncDirection.localToRemote
        /// 2. key info list should contain the keys
        /// 3. sync status should be success
      });
    });

    group('A group of test to verify onDone callback', () {
      test('A test to verify onDone callback is called on success', () {
        /// Preconditions:
        /// 1. server and local are in sync
        /// 2. In the local keystore have 5 uncommitted entries
        ///
        /// Operation:
        ///  Initiate sync
        ///
        /// Assertions:
        /// 1. onDone callback should be called
        /// 2. sync status should be success
      });

      test('A test to verify syncResult in onDone callback when failure occur',
          () {
        /// Preconditions:
        /// 1. The serverCommitId is greater than localCommitId
        /// 2. Have uncommitted entries on the client side
        /// 3. SyncResult.syncStatus is set to notStarted
        ///
        /// Assertions:
        /// 1. The error is encapsulated in the SyncResult.atClientException
        /// 2. The SyncResult.syncStatus is set to failure
        /// 3. The syncResult.lastSyncedOn is set to sync completion time
      });
    });
  });

  group('A group of test to verify sync conflict resolution', () {
    test(
        'A test to verify when sync conflict info when key present in'
        'uncommitted entries and in server response of sync', () {
      /// Preconditions:
      /// 1. The server commit id should be greater than local commit id
      /// 2. The server response should an contains a entry - @alice:phone@bob
      /// 3. On the client, in the uncommitted list have the same as above with
      /// a different value
      ///
      /// Assertions:
      /// 1. The key should be added to the keyListInfo
    });
  });
}
