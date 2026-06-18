import 'package:at_client/src/util/sync_util.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of sync util tests', () {
    // The PKAM Private keys should not be sync'ed to server
    test('sync util check pkam private key sync skip', () {
      var shouldSync = SyncUtil.shouldSync(AtConstants.atPkamPrivateKey);
      expect(shouldSync, false);
    });
    // The PKAM Public keys should not be sync'ed to server
    test('sync util check pkam public key sync skip', () {
      var shouldSync = SyncUtil.shouldSync(AtConstants.atPkamPublicKey);
      expect(shouldSync, false);
    });
    // The encryption private keys should not be sync'ed to server
    test('sync util check encryption private key sync skip', () {
      var shouldSync = SyncUtil.shouldSync(AtConstants.atEncryptionPrivateKey);
      expect(shouldSync, false);
    });
    // The encryption public key should be sync'ed to server
    test('sync util check encryption public key sync skip', () {
      var shouldSync = SyncUtil.shouldSync(AtConstants.atEncryptionPublicKey);
      expect(shouldSync, true);
    });

    test('sync util check normal key sync skip', () {
      var shouldSync = SyncUtil.shouldSync('phone@bob');
      expect(shouldSync, true);
    });
  });
}
