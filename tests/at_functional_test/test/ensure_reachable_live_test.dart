// The nskey surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// **Arm C of the startup-tail differential**: the client whose tail was
/// abandoned asks to be made reachable, and is.
///
/// Read with its two pairs. `seeding_tail_runs_live_test.dart` shows a living
/// client publishes on its own; `seeding_tail_abandoned_live_test.dart` shows
/// a stopped one publishes nothing while `startupComplete` resolves anyway.
/// This one takes the *same* stopped client — the shape a CLI tool, a cron job
/// or a piped-stdin notifier actually has — and shows the supported way out.
///
/// ⚠️ **Its own file for the same reason as the others**: `AtClientManager` is
/// a per-isolate singleton that re-serves the client it already built, so a
/// bootstrap that has not yet run needs a fresh isolate.
///
/// `ensureReachable` is on the **`AtClient` interface**, so nothing here
/// downcasts to reach it — the downcast below is only to stop the startup
/// tail, which is a test manoeuvre and not something an app does.
void main() {
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

    // Reproduce the defect first, so what follows is a rescue and not a
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
    expect(
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, namespace),
        isNotNull,
        reason: 'and the outcome is not merely a claim — the advertisement is '
            'on the atServer, fetched by the exact lookup a sender uses');

    // Idempotent and cheap on every start, which is what makes it safe to
    // call unconditionally. A second call must not mint a second generation:
    // that would rotate the namespace key out from under any peer that had
    // already fetched the first.
    final again = await atClient.ensureReachable(namespace);
    expect(again.outcome, AtReachability.alreadyReachable,
        reason: 'the second call finds the key and does nothing, so an app may '
            'call this on every start without rotating its own namespace key '
            'each time');
    expect(again.isReachable, isTrue);
  }, timeout: Timeout(Duration(minutes: 3)));
}
