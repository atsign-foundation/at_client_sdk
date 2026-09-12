// The substrate and the signing root are @experimental; driving them is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The signing-root pull, as far as a single client can reach it.
///
/// The pull is the only route left to an enrollment that was offline when it
/// was approved: the root is atSign-level and carries no namespace, so it never
/// rides the `enroll:listns` fan-out, and nothing re-mints a root that is
/// already published.
///
/// The full round trip — seeker asks, holder answers, private reaches the
/// keyfile — is not driven here, because it needs two principals and this
/// file has one: a seeker that lacks the root and a holder that has it. The
/// atSign's own credential, which is what this file authenticates with, does
/// not ask for a root, since its route to a missing one is to mint one.
/// `signing_root_pull_two_enrollments_test.dart` drives the round trip between
/// two APKAM enrollments and proves UC-B5.1.
///
/// The atServer is not what keeps this file off that path. Since at_server
/// 3.16.4 a connection authenticated with the atSign's own keys is judged as
/// the `primary` enrollment, and `enroll:listns` answers it with a roster that
/// names `primary`; only an unauthenticated connection is refused.
///
/// What this file does prove live is the entitlement guard below.
void main() {
  TestUtils.isolateStorage('signing_root_pull_test');
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: PqPosture.legacy);
    atClient = manager.atClient;
  });

  /// Two independently-constructed parties over one client: same atSign, but
  /// each generates its own X-Wing keypair, so they have distinct kpids —
  /// which is all envelope addressing turns on.
  Future<AtClientSecretSharing> newParty() async {
    final party = AtClientSecretSharing(atClient)
      ..sendWakeUpNotification = false;
    await party.register();
    return party;
  }

  test('an enrollment not entitled to the root does not ask for it', () async {
    final seeker = await newParty();
    final seekerKeys = InMemoryAtKeysIo();
    await seekerKeys.write(atSign, AtKeys());

    // The only thing that changes is the privilege answer: a broadcast
    // happening anyway would show the guard is decorative.
    expect(
        await PqSigningRoot(atClient, keysIo: seekerKeys)
            .requestPrivateIfAbsent(
          isFullyPrivileged: () async => false,
          sharing: seeker,
          namespace: namespace,
        ),
        0,
        reason: 'only a fully privileged enrollment may hold the key that '
            'vouches for every enrollment on the atSign; a scoped one asking '
            'would be refused, and the asking itself tells every holder that '
            'something unentitled is looking for it');
  });
}
