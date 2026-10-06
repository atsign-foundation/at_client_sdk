// The nskey surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A client whose startup tail was abandoned — the shape a CLI tool, a cron
/// job or a piped-stdin notifier has — asks to be made reachable, and is.
///
/// NOTE: its own file because `AtClientManager` is a per-isolate singleton
/// that re-serves the client it already built, so a bootstrap that has not yet
/// run needs a fresh isolate.
void main() {
  TestUtils.isolateStorage('ensure_reachable_live_test');
  late String atSign;
  final namespace = 'ensurereach${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('a client with an abandoned tail can make itself reachable', () async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());

    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: PqPosture.pqActive);
    final atClient = manager.atClient;

    // Abandon the tail first, so what follows is a rescue and not a
    // demonstration against a client that was going to publish anyway.
    (atClient as AtClientImpl).pqBootstrap!.stop();
    await atClient.pqBootstrap!.startupComplete
        .timeout(const Duration(seconds: 30));
    expect(
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, namespace),
        isNull,
        reason: 'the precondition and the reason this arm exists: the tail was '
            'abandoned, so nothing is published and no peer can seal here');

    final rescued = await atClient.ensureReachable(namespace);

    expect(rescued.outcome, AtReachability.published,
        reason: 'it reports WHAT HAPPENED, not that something finished. '
            '`published` rather than `alreadyReachable` is the whole point of '
            'the distinction: this call did the work, and a caller that wants '
            'to log or meter its first run can tell');
    expect(rescued.isReachable, isTrue);
    expect(rescued.holdsPrivate, isTrue,
        reason: 'checked against the advertisement the atServer now serves, '
            'not assumed from having minted it');
    expect(
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, namespace),
        isNotNull,
        reason: 'and the outcome is not merely a claim — the advertisement is '
            'on the atServer, fetched by the exact lookup a sender uses');

    final again = await atClient.ensureReachable(namespace);
    expect(again.outcome, AtReachability.alreadyReachable,
        reason: 'the second call finds the key and does nothing, so an app may '
            'call this on every start without rotating its own namespace key '
            'each time');
    expect(again.isReachable, isTrue);
    expect(again.holdsPrivate, isTrue,
        reason: 'the client that minted the key holds its private, so it can '
            'open what peers seal here');
  }, timeout: Timeout(Duration(minutes: 3)));

  test(
      'a client of the same atSign that was never conveyed the private does '
      'not hold it', () async {
    // NOTE: one live client per principal; the one above has done its work.
    await AtClientManager.getInstance().atClient.stop();
    final loader = AtEncryptionKeysLoader.getInstance();
    final other = '${namespace}other';
    // The demo keys are this atSign's credential and hold none of the nskey
    // privates the first client filed in its own key source.
    final second = await Atsign(atSign).open(
        keys: InMemoryAtKeysIo.holding(
            atSign, loader.createAtKeysFromDemoKeys(atSign)),
        preference: TestUtils.getPreference(atSign, posture: PqPosture.pqActive)
          ..namespace = other,
        namespace: other,
        storage: TestUtils.storageForPrincipal(atSign, 'unheld'));
    addTearDown(second.stop);
    await loader.setEncryptionKeys(second, atSign);
    await (second as AtClientImpl).pqBootstrap!.startupComplete;

    final result = await second.ensureReachable(namespace);

    expect(result.outcome, AtReachability.alreadyReachable,
        reason: 'the first client published the key for this namespace');
    expect(result.isReachable, isTrue);
    expect(result.holdsPrivate, isFalse,
        reason: 'the private was filed by the client that minted it and '
            'conveyed to nobody, so peers can seal here and this client '
            'cannot open what they seal: the arm the two assertions above '
            'cannot show, and the one a constant true would hide');
  }, timeout: Timeout(Duration(minutes: 3)));
}
