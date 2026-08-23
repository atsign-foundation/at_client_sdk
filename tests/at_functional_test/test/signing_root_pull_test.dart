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

/// The signing-root pull, as far as this harness can reach it.
///
/// The pull is the only route left to an enrollment that was offline when it
/// was approved: the root is atSign-level and carries no namespace, so it
/// never rides the `enroll:listns` fan-out, and nothing re-mints a root that
/// is already published. `requestPrivateIfAbsent` is the
/// initiator that was missing — before it, `requestSecret` had zero call sites
/// in `lib/`.
///
/// **What is NOT proven here, and why.** The full round trip — seeker asks,
/// holder answers, private reaches the keyfile — cannot be driven from this
/// harness, and the reason was established on the wire rather than guessed.
///
/// The pull needs APKAM authentication on **both** sides. The requester needs
/// it to enumerate holders, and the responder needs it to authorize the
/// requester before answering — that authorization resolves the sender's kpid
/// against the key packages registered for the namespace, which is deliberate
/// defence in depth over the atServer's own delivery gate. Both go through
/// `enroll:listns`, and the atServer refuses it for a client authenticating
/// with the atSign's own keys, which is what this harness does. Under FINEST
/// logging the holder is seen picking the request up and failing with
/// *"Client authentication failed : enroll:listns requires APKAM
/// authentication"*, leaving the envelope unconsumed.
///
/// So proving the round trip needs a fixture with two real approved APKAM
/// enrollments, each with its own authenticated client. That does not exist in
/// this package yet; UC-B5.1 stays blocked on it, and decisions.md 30-31 carry
/// the detail.
///
/// What this file does prove live is the entitlement guard below.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
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

    // The control for the test above, on the same live wire: the only thing
    // that changes is the privilege answer, so a broadcast happening anyway
    // would show the guard is decorative.
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
