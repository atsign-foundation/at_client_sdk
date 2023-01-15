import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:test/test.dart';

void main() {
  group('A group of switch atsign tests', () {
    test('test switch atsign - check atsign name', () async {
      final aliceAtSign = '@alice';
      final atClientManager = AtClientManager(aliceAtSign);
      final alicePreference = AtClientPreference();
      await atClientManager.setCurrentAtSign(
          aliceAtSign, 'wavi', alicePreference);
      expect(atClientManager.atClient.getCurrentAtSign(), aliceAtSign);
      final bobPreference = AtClientPreference();
      final bobAtSign = '@bob';
      await atClientManager.setCurrentAtSign(bobAtSign, 'buzz', bobPreference);
      expect(atClientManager.atClient.getCurrentAtSign(), bobAtSign);
    });

    test('test switch atsign - check progress listener cleared', () async {
      final aliceAtSign = '@alice';
      final atClientManager = AtClientManager(aliceAtSign);
      final alicePreference = AtClientPreference();
      await atClientManager.setCurrentAtSign(
          aliceAtSign, 'wavi', alicePreference);
      expect(atClientManager.atClient.getCurrentAtSign(), aliceAtSign);
      atClientManager.atClient.syncService
          .addProgressListener(AliceSyncProgressListener());
      final bobPreference = AtClientPreference();
      final bobAtSign = '@bob';
      await atClientManager.setCurrentAtSign(bobAtSign, 'buzz', bobPreference);
      atClientManager.atClient.syncService
          .addProgressListener(BobSyncProgressListener());
      expect(atClientManager.atClient.getCurrentAtSign(), bobAtSign);
      expect(
          (atClientManager.atClient.syncService as SyncServiceImpl)
              .syncProgressListenerSize(),
          1);
    });
  });
}

class AliceSyncProgressListener implements SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    print('alice listener event ${syncProgress.toString()}');
  }

  @override
  String toString() {
    return 'AliceSyncProgressListener';
  }
}

class BobSyncProgressListener implements SyncProgressListener {
  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    print('bob listener event ${syncProgress.toString()}');
  }

  @override
  String toString() {
    return 'BobSyncProgressListener';
  }
}
