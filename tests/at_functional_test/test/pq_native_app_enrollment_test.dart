// The enrollment key-package surface is @experimental; enrolling drives it.
// ignore_for_file: experimental_member_use

@Timeout(Duration(minutes: 15))
@Tags(['pq'])
library;

import 'dart:io';

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart'
    show enrolAndAuthenticate;
import 'package:test/test.dart';

import 'test_utils.dart';

/// An app can enrol post-quantum from birth, and then does not retrofit.
///
/// Until `AtEnrollmentRequest` carried a `signingAlgo`, an app enrolling over
/// OTP always got an RSA-2048 APKAM authentication keypair — there was no way
/// to ask for anything else. On an atSign whose deployment had moved to
/// post-quantum, every install therefore created an RSA-authenticating
/// enrollment, which the client retrofitted away during its first
/// construction: a discarded enrollment per install, and an RSA credential
/// live for the atServer's grace window on an atSign that believed it had
/// left RSA behind.
///
/// The differential is the second half. Asserting only that an mldsa65
/// enrollment comes back mldsa65 would pass just as well for a build that
/// minted RSA and immediately retrofitted, because the client would end up on
/// ML-DSA either way. What distinguishes the fix from the defect is that the
/// enrollment id does NOT change — nothing was thrown away.
void main() {
  final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final namespace = 'pqnat$runId';

  late AtClient approver;

  setUpAll(() async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final loader = AtEncryptionKeysLoader.getInstance();
    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, namespace, TestUtils.getPreference(atSign,
            posture: legacyPlusPqProviders),
        atKeysIo: keysIo,
        atChops: loader.createAtChopsFromDemoKeys(atSign));
    await loader.setEncryptionKeys(manager.atClient, atSign);
    await AtClientSecretSharing.forClient(manager.atClient).register();
    approver = manager.atClient;
  });

  /// One enrolment at [signingAlgo], under a pqActive preference so that the
  /// client would retrofit if its key material were not already strong enough.
  Future<({String enrolledAs, String runningAs, AtKeys keys})> enrolAt(
      SigningAlgoType signingAlgo, String label) async {
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: PqPosture.pqActive),
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      namespaces: {namespace: 'rw'},
      // `(appName, deviceName)` is one-shot server state.
      deviceName: 'pqnat-$label-$runId',
      atKeysIo: keysIo,
      signingAlgo: signingAlgo,
    );
    final runningAs = enrolled.client.enrollmentId!;
    stdout.writeln('##NATIVE## $label: enrolledAs=${enrolled.enrollmentId} '
        'runningAs=$runningAs');
    return (
      enrolledAs: enrolled.enrollmentId,
      runningAs: runningAs,
      keys: await keysIo.read(atSign),
    );
  }

  test('an mldsa65 app enrolment is post-quantum from birth and does not '
      'retrofit, where an rsa2048 one still does', () async {
    final native = await enrolAt(SigningAlgoType.mldsa65, 'mldsa65');
    final legacy = await enrolAt(SigningAlgoType.rsa2048, 'rsa2048');

    // The fix.
    expect(native.runningAs, native.enrolledAs,
        reason: 'an enrollment minted with an ML-DSA-65 APKAM key already '
            'authenticates the way a pqActive posture wants, so no retrofit '
            'is due and the client must still be running as the enrollment it '
            'was given. A different id means it threw that enrollment away '
            'and made another - the defect this exists to close');

    expect(native.keys.authenticationAlgorithmFor(native.enrolledAs),
        SigningAlgoType.mldsa65,
        reason: 'the enrolment was submitted as mldsa65, so the keyfile must '
            'hold ML-DSA-65 typed authentication material under that id. If '
            'it holds nothing, the algorithm never reached the wire and the '
            'atServer recorded the absent-field default');

    // The flat fields hold the SAME keypair, deliberately. What must not
    // happen is flat and typed naming DIFFERENT enrollments — that is a
    // retrofitted keyfile, where the flat fields belong to the enrollment left
    // behind. Here there is one enrollment and the keyfile's own enrollmentId
    // names it, so both resolve to one key; and the approval handshake needs
    // the keypair and the symmetric key out of a single `toAtChops`.
    // ignore: deprecated_member_use
    expect(native.keys.apkamPublicKey, isNotNull,
        reason: 'the flat fields carry this enrollment\'s own keypair too, '
            'which is what lets the approval handshake build one AtChops '
            'holding both it and the symmetric key');

    // The control. Without it, "did not retrofit" would pass for a build where
    // nothing retrofits at all - including one where the posture is ignored.
    expect(legacy.runningAs, isNot(legacy.enrolledAs),
        reason: 'an rsa2048 enrolment under a pqActive posture must STILL '
            'retrofit, because its key material is not what the posture '
            'wants. If this one also kept its id, the assertion above is not '
            'measuring the algorithm - it is measuring a retrofit that has '
            'stopped happening for some other reason');
  });
}
