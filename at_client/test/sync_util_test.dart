import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:test/test.dart';

void main() {
  group('A group of sync util tests', () {
    // The PKAM Private keys should not be sync'ed to server
    test('sync util check pkam private key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSync(AT_PKAM_PRIVATE_KEY);
      expect(isSyncRequired, true);
      var shouldSync = SyncUtil.shouldSync(AT_PKAM_PRIVATE_KEY);
      expect(shouldSync, false);
    });
    // The PKAM Public keys should not be sync'ed to server
    test('sync util check pkam public key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSync(AT_PKAM_PUBLIC_KEY);
      expect(isSyncRequired, true);
      var shouldSync = SyncUtil.shouldSync(AT_PKAM_PUBLIC_KEY);
      expect(shouldSync, false);
    });
    // The encryption private keys should not be sync'ed to server
    test('sync util check encryption private key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSync(AT_ENCRYPTION_PRIVATE_KEY);
      expect(isSyncRequired, true);
      var shouldSync = SyncUtil.shouldSync(AT_ENCRYPTION_PRIVATE_KEY);
      expect(shouldSync, false);
    });
    // The encryption public key should be sync'ed to server
    test('sync util check encryption private key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSync(AT_ENCRYPTION_PUBLIC_KEY);
      expect(isSyncRequired, false);
      var shouldSync = SyncUtil.shouldSync(AT_ENCRYPTION_PUBLIC_KEY);
      expect(shouldSync, true);
    });

    test('sync util check normal key sync skip', () {
      var isSyncRequired = SyncUtil.shouldSync('phone@bob');
      expect(isSyncRequired, false);
      var shouldSync = SyncUtil.shouldSync('phone@bob');
      expect(shouldSync, true);
    });

    test('test in sync - no commits on local and server', () {
      var isInSync = SyncUtil.isInSync(null, null, null);
      expect(isInSync, true);
    });

    test('test in sync - uncommitted entries in local and commit ids are null',
        () {
      var entries = <CommitEntry>[];
      var entry =
          CommitEntry('public:phone@alice', CommitOp.UPDATE, DateTime.now());
      entries.add(entry);
      var isInSync = SyncUtil.isInSync(entries, null, null);
      expect(isInSync, false);
    });

    test(
        'test in sync - NO uncommitted entries in local and server commit id > local commit id',
        () {
      var isInSync = SyncUtil.isInSync(null, 1, 5);
      expect(isInSync, false);
    });

    test(
        'test in sync - uncommitted entries in local commit id > server commit id',
        () {
      var entries = <CommitEntry>[];
      var entry =
          CommitEntry('public:phone@alice', CommitOp.UPDATE, DateTime.now());
      entries.add(entry);
      var isInSync = SyncUtil.isInSync(entries, 5, 1);
      expect(isInSync, false);
    });
  });
}
