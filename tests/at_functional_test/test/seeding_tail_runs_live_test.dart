// The nskey surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// **Arm A of a two-file differential**: does a client's unawaited startup
/// tail publish an nskey advertisement on its own?
///
/// Its pair is `seeding_tail_abandoned_live_test.dart`, which runs the same
/// construction and stops the tail. ⚠️ **The two arms are in separate files
/// deliberately, and it is not stylistic**: `AtClientManager` is a per-isolate
/// singleton that re-serves the client it already built, so a second arm in
/// this file would be handed the client this one left running — with its
/// bootstrap already finished. Separate files are separate isolates, which is
/// the only way each arm gets a bootstrap that has not yet run. Keep the two
/// namespaces run-unique and the posture identical, or the arms differ in more
/// than the one thing under test.
///
/// ⚠️ **`nskey_seeding_live_test.dart` does not cover this**, though its doc
/// comment says it exists to catch "whether the path runs at all — a client
/// whose seeding silently never fired". It builds at `PqPosture.legacy`, where
/// `seedNamespaceKeys` is **false**, and calls `NskeySeeding.seed()` by hand;
/// a client whose startup tail never fires passes it. This file is the arm
/// that would have gone red.
void main() {
  late String atSign;
  // Run-unique: against a namespace something has already minted for, seeding
  // adopts the existing advertisement and every assertion below would hold for
  // the absence of work rather than for the work.
  final namespace = 'seedalive${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
  });

  test('a client left alive publishes its advertisement via the startup tail',
      () async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());

    final startedAt = DateTime.now();
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: PqPosture.pqActive);
    final atClient = manager.atClient;

    expect(atClient.getPreferences()?.seedNamespaceKeys, isTrue,
        reason: 'the precondition, checked rather than assumed: at a posture '
            'that does not seed, publishing nothing is correct behaviour and '
            'this arm would measure the posture instead of the tail');

    // NOTHING calls seed() here, which is the whole point — the question is
    // whether the tail AtClientImpl._init fired gets there on its own.
    final ring = PublishedNskeyKeyRing(atClient);
    NskeyAdvertisement? advertised;
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      advertised = await ring.currentPublic(atSign, namespace);
      if (advertised != null) break;
    }

    expect(advertised, isNotNull,
        reason: 'a client whose process lives publishes within seconds. This '
            'is also the POSITIVE CONTROL its paired file depends on: without '
            'it, that file measuring "nothing was published" would say nothing '
            'about stopping, because a rig that cannot seed at all produces '
            'the same red. Three earlier reproduction attempts died exactly '
            'there');
    expect(
        DateTime.now().difference(startedAt),
        lessThan(const Duration(seconds: 30)),
        reason: 'and it is prompt — measured at ~1s on 2026-08-27, so the '
            '15-second window the paired arm waits before concluding nothing '
            'was published is a measurement rather than an impatient guess');
  }, timeout: Timeout(Duration(minutes: 3)));
}
