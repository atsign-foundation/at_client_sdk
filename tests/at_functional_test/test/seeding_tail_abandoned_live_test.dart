// The nskey surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// **Arm B of a two-file differential**: a client whose startup tail is
/// stopped publishes nothing, and the only signal an app has says nothing
/// about it.
///
/// Its pair — and its positive control — is
/// `seeding_tail_runs_live_test.dart`, where the identical construction at the
/// identical posture publishes in about a second. Read the two together: on
/// its own, "no advertisement appeared" is equally well explained by a rig
/// that cannot seed for this namespace at all, and that is precisely how three
/// earlier reproduction attempts were lost.
///
/// ⚠️ **Separate files because `AtClientManager` is a per-isolate singleton**
/// that re-serves the client it already built. Two arms in one file would
/// share one bootstrap, and whichever ran second would measure nothing.
///
/// **What this stands for.** `stop()` is the in-tree stand-in for the process
/// exiting: it breaks the step loop at the next boundary, which is what a
/// short-lived client's death does to the unawaited tail. The real case is
/// ordinary — a client driven from a script with piped stdin sends one message
/// and exits, the same shape as a CLI tool, a cron job or a one-shot notifier.
/// Confirmed live in both directions on 2026-08-26 by the at_talk demo
/// session, where the only variable was the client's LIFETIME.
void main() {
  late String atSign;
  final namespace = 'seedstopped${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('a stopped tail publishes nothing, and startupComplete resolves anyway',
      () async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());

    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: PqPosture.pqActive);
    final atClient = manager.atClient as AtClientImpl;

    expect(atClient.getPreferences()?.seedNamespaceKeys, isTrue,
        reason: 'the same precondition the paired arm checks: at a posture '
            'that does not seed, publishing nothing would be correct and this '
            'test would pass for the wrong reason');

    atClient.pqBootstrap!.stop();

    // The only signal an application has, and what it says about a startup
    // that did not run.
    await atClient.pqBootstrap!.startupComplete
        .timeout(const Duration(seconds: 30));

    final ring = PublishedNskeyKeyRing(atClient);
    NskeyAdvertisement? advertised;
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      advertised = await ring.currentPublic(atSign, namespace);
      if (advertised != null) break;
    }

    expect(advertised, isNull,
        reason: 'the defect: the tail was abandoned before it seeded, so this '
            'atSign has no published namespace key. It can still SEND — '
            'sending needs the recipient\'s key, not its own — while no peer '
            'can seal to it, and the peer is where the symptom surfaces, '
            'naming the wrong party. 15 seconds against a paired arm that '
            'published in about one');
  }, timeout: Timeout(Duration(minutes: 2)));
}
