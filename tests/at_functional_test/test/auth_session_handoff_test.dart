import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Exercises the keyfile → client hand-off end-to-end against a live
/// atServer.
///
/// The point of this test — which a unit suite can't prove — is that the
/// client builds its OWN connection from the [AtKeysIo] source alone: no
/// signer and no connection are injected from anywhere. If the client's
/// derived `AtChops` PKAMs on its fresh socket, a put/get round-trip succeeds.
void main() {
  TestUtils.isolateStorage('auth_session_handoff_test');
  late String atSign;
  final namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test(
      'open from a keyfile builds its own connection and round-trips a '
      'put/get', () async {
    // The .atKeys fixture is the key *source* — same file a real app would hold.
    final atKeysIo = FileAtKeysIo(
      filePath: (_) => 'test/testData/${atSign}_key.atKeys',
    );

    // 1. Open the client on the source. Nothing else is handed across: the
    //    client derives its own AtChops from the keys and PKAMs on a fresh
    //    socket.
    final atClient = await Atsign(atSign).open(
        keys: atKeysIo,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
        namespace: namespace,
        storage: TestUtils.storageFor(atSign));
    AtClientManager.getInstance().use(atClient);

    // The client built its own crypto context and reached the atServer on a
    // connection of its own.
    expect(atClient.atChops, isNotNull);
    expect(atClient.connection.current.isOnline, isTrue,
        reason: 'the one connect attempt open makes is the PKAM that proves '
            'the derived AtChops signs');

    // 2. Full round-trip. The put drives the connection's first authenticated
    //    verb, and the get closes the loop through self encryption.
    final key = AtKey()
      ..key = 'handoff_selfkey'
      ..sharedBy = atSign;
    final value = 'handoff-$namespace-value';

    expect(await atClient.put(key, value), true);
    final getResult = await atClient.get(key);
    expect(getResult.value, value);

    // And it survives a sync + remote fetch — the write really landed.
    await FunctionalTestSyncService.getInstance()
        .syncData(syncSvc: atClient.syncService);
    final remote = await atClient.get(
      key,
      getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
    );
    expect(remote.value, value);
  });
}
