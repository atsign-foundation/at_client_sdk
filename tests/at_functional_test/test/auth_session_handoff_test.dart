import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/sync_service.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Exercises the auth→client hand-off via [AtAuthSession] end-to-end against a
/// live atServer.
///
/// The point of this test — which a unit suite can't prove — is that the client
/// rebuilds its OWN connection from the [AtKeysIo] source alone: no `AtChops`
/// and no `AtLookUp` are injected from auth. If the client's derived `AtChops`
/// PKAMs on its fresh socket, a put/get round-trip succeeds.
void main() {
  late String atSign;
  final namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test(
      'authenticate → session → fromAuthSession rebuilds its own connection '
      'and round-trips a put/get', () async {
    // The .atKeys fixture is the key *source* — same file a real app would hold.
    final atKeysIo = FileAtKeysIo(
      filePath: (_) => 'test/testData/${atSign}_key.atKeys',
    );

    final rootDomain = AtRootDomain(
      TestUtils.getPreference(atSign).rootDomain,
      TestUtils.rootServerPort,
    );

    // 1. Authenticate. The response carries an explicit session, not a live
    //    AtChops/AtLookUp for the client to adopt.
    final authResponse = await AtAuth.create().authenticate(
      AtAuthRequest(atSign, atKeysIo: atKeysIo, rootDomain: rootDomain)
        ..namespace = namespace,
    );
    expect(authResponse.isSuccessful, true);
    expect(authResponse.session, isNotNull);
    expect(authResponse.session!.atKeysIo, same(atKeysIo));

    // 2. Hand the session to the client. Crucially: no atChops / atLookUp — the
    //    client must derive its own AtChops from session.atKeysIo and PKAM on a
    //    fresh socket.
    final preference = TestUtils.getPreference(atSign);
    final atClientManager = await AtClientManager.getInstance()
        .fromAuthSession(authResponse.session!, preference);
    final atClient = atClientManager.atClient;

    // The client built its own crypto context (not one injected by auth).
    expect(atClient.atChops, isNotNull);

    // 3. Full round-trip. The put drives the rebuilt connection's first
    //    authenticated verb — so a successful put IS the proof that the derived
    //    AtChops PKAMed on its own fresh socket. The get closes the loop through
    //    self encryption.
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
