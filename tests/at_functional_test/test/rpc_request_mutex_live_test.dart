// The enrollment fixture is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

library;

import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/sync_util.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The AtRpc request mutex against a live atServer: two responders for one
/// atSign, each its own client, and a requester on another atSign.
///
/// The scenario tests share their titles with
/// `features/at_client/rpc_request_mutex.feature`. The namespace is run-unique,
/// so no other file's responders or request ids meet these.
void main() {
  TestUtils.isolateStorage('rpc_request_mutex_live_test');
  late String alice;
  late String bob;
  late AtClient owner;
  late AtClient enrolled;
  late AtClient requester;
  late AtRpcClient rpcClient;
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'rpcmutex$runId';
  const domain = 'mutex';
  const rootDomain = 'vip.ve.atsign.zone';

  /// The responder that handled each request, in order, with its request id.
  final handled = <(String, int)>[];

  /// Request notifications each of @alice's clients received, by client.
  final arrived = <String, int>{'owner': 0, 'enrolled': 0};
  final listening = <StreamSubscription<AtNotification>>[];

  AtRpc responder(AtClient client, String label) => AtRpc.server(
      atClient: client,
      baseNameSpace: namespace,
      domainNameSpace: domain,
      requestHandler: (request, from) async {
        handled.add((label, request.reqId));
        return AtRpcResp(
            reqId: request.reqId,
            respType: AtRpcRespType.success,
            payload: {'by': label});
      },
      allowList: {bob.toAtsign()},
      allowAll: false,
      enableRequestMutex: true);

  /// Counts the request notifications [client] receives, decrypted or not.
  void countArrivals(AtClient client, String label) {
    listening.add(client.notificationService
        .subscribe(
            regex: 'request.\\d+.$domain.__rpcs.$namespace@',
            shouldDecrypt: false)
        .listen((_) => arrived[label] = arrived[label]! + 1));
  }

  Future<int> serverCommitId() async =>
      await SyncUtil()
          .getLatestServerCommitId(owner.getRemoteSecondary()!, '') ??
      -1;

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(alice, AtKeys());
    owner = (await TestUtils.initAtClient(alice, namespace,
            atKeysIo: keysIo, posture: legacyPlusPqProviders))
        .atClient;
    enrolled = (await enrolAndAuthenticate(
      approver: owner,
      atSign: alice,
      namespace: namespace,
      preference: TestUtils.getPreference(alice, posture: PqPosture.legacy),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      deviceName: 'rpcmutex-$runId',
      storage: TestUtils.storage,
    ))
        .client;
    final bobKeys = InMemoryAtKeysIo.holding(bob,
        AtEncryptionKeysLoader.getInstance().createAtKeysFromDemoKeys(bob));
    await TestUtils.seedIfCredentialless(bob, bobKeys);
    requester = await Atsign(bob).open(
        keys: bobKeys,
        preference: TestUtils.getPreference(bob, posture: PqPosture.legacy),
        namespace: namespace,
        storage: TestUtils.storageFor(bob));
    rpcClient = AtRpcClient(
        serverAtsign: alice,
        atClient: requester,
        baseNameSpace: namespace,
        domainNameSpace: domain);
    await rpcClient.rpc.ready();
    countArrivals(owner, 'owner');
    countArrivals(enrolled, 'enrolled');
  });

  tearDownAll(() async {
    for (final s in listening) {
      await s.cancel();
    }
    await requester.stop();
    await enrolled.stop();
    await owner.stop();
  });

  test('Exactly one of two responders handles a request', () async {
    // NOTE: the control first. The enrolled responder alone must handle a
    // request, or a second responder that never handles anything would pass
    // below for the wrong reason: one that could not read the request at all.
    final second = responder(enrolled, 'enrolled')..start();
    await second.ready();
    expect(await rpcClient.call({'q': 'control'}).timeout(Duration(minutes: 1)),
        {'by': 'enrolled'});
    expect(handled.map((h) => h.$1), ['enrolled']);

    final first = responder(owner, 'owner')..start();
    await first.ready();
    handled.clear();
    arrived.updateAll((_, __) => 0);

    final answer =
        await rpcClient.call({'q': 'race'}).timeout(Duration(minutes: 1));
    // NOTE: the loser's attempt can land after the winner's answer.
    await Future<void>.delayed(Duration(seconds: 3));

    expect(arrived, {'owner': 1, 'enrolled': 1},
        reason: 'both responders received the request, so each had the chance '
            'to handle it');
    expect(handled, hasLength(1),
        reason: 'and exactly one did: the other lost the lock on its id');
    expect(answer, {'by': handled.single.$1});
  });

  test('A request\'s lock records no commit', () async {
    handled.clear();
    // NOTE: the control first: if a committed write does not move the commit
    // id read here, the zero below means nothing.
    var before = await serverCommitId();
    await owner.put(AtKey.fromString('committed.$namespace$alice'), 'control',
        putRequestOptions: PutRequestOptions()
          ..shouldEncrypt = false
          ..useRemoteAtServer = true);
    expect(await serverCommitId() - before, greaterThan(0));
    before = await serverCommitId();

    await rpcClient.call({'q': 'commit'}).timeout(Duration(minutes: 1));
    await Future<void>.delayed(Duration(seconds: 3));

    expect(handled, hasLength(1));
    final lock = '${handled.single.$2}.session_mutexes.$domain.__rpcs.'
        '$namespace$alice';
    final meta = await owner
        .getRemoteSecondary()!
        .executeCommand('llookup:meta:$lock\n', auth: true);
    expect(jsonDecode(meta!.replaceFirst('data:', ''))['immutable'], isTrue,
        reason: 'the control: the lock was taken on the atServer');
    expect(await serverCommitId() - before, 0,
        reason: 'and taking it, and answering, moved the commit log nowhere');
  });
}
