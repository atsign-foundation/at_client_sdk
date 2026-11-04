import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_io.dart'
    show CacheableSecondaryAddressFinder, FileAtKeysIo, secureSocketLookUps;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// Catalogue: features/at_client/web_safe.feature
void main() {
  TestUtils.isolateStorage('native_program_test');

  test('A native program keeps what it had', () async {
    final String atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final String peer = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final runId = const Uuid().v4();
    final preference =
        TestUtils.getPreference(atSign, posture: PqPosture.legacy);

    final client = await Atsign(atSign).open(
        keys:
            FileAtKeysIo(filePath: (_) => 'test/testData/${atSign}_key.atKeys'),
        preference: preference,
        namespace: 'wavi',
        storage: TestUtils.storageFor(atSign),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: CacheableSecondaryAddressFinder(
            preference.rootDomain, preference.rootPort));
    addTearDown(client.stop);

    expect(client.connection.current.isOnline, isTrue,
        reason: 'it opens: the client authenticated from its keyfile over '
            'TLS, at the atServer the atDirectory named');

    final own = AtKey()
      ..key = 'native-$runId'
      ..sharedBy = atSign
      ..namespace = 'wavi';
    expect(await client.put(own, 'kept'), isTrue);
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: client.syncService);
    final remote = await client.get(own,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    expect(remote.value, 'kept',
        reason: 'it syncs: the local write reached the atServer');

    final shared = AtKey()
      ..key = 'native-$runId'
      ..sharedWith = peer
      ..namespace = 'wavi';
    final notified = await client.notificationService
        .notify(NotificationParams.forUpdate(shared, value: 'kept'));
    expect(notified.notificationStatusEnum, NotificationStatusEnum.delivered,
        reason: 'it notifies: the peer\'s atServer, found through the same '
            'atDirectory, took delivery');
  });
}
