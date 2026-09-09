// The enrollment fixture is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// APKAM authentication verifies against the **enrollment record**, never the
/// algorithm the client names on the wire.
///
/// The attack this forbids is concrete: if the atServer picked its verifier
/// from the `signingAlgo` field of the incoming `pkam:` command, a caller could
/// name whichever algorithm suited it. The record's `apkamPublicKey` and its
/// stored `signingAlgo` are the only authority.
///
/// The client API cannot express the mismatch — `AtLookupImpl.signingAlgoType`
/// drives both the signature at_chops produces and the value put on the wire —
/// so the `pkam:` command is built by hand, always signing RSA with the
/// enrollment's real keypair and varying only the algorithm claimed. Both arms
/// are therefore expected to authenticate: the mldsa65 arm succeeding is
/// precisely the claim, because an atServer reading the wire would attempt
/// ML-DSA verification of an RSA signature and fail.
void main() {
  TestUtils.isolateStorage('pkam_record_authoritative_test');
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';
  const rootDomain = 'vip.ve.atsign.zone';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo,
            posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  test('the wire signingAlgo is a claim, and the record decides', () async {
    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      // Unique per run: the atServer refuses a second enrollment carrying an
      // (appName, deviceName) pair that already has one approved.
      deviceName: 'pkamalgo-${DateTime.now().microsecondsSinceEpoch}',
    storage: TestUtils.storage,
  );

    /// Authenticates on a fresh connection, signing RSA with the enrollment's
    /// real keypair while telling the atServer [claimedAlgo].
    Future<String?> authenticateClaiming(String claimedAlgo) async {
      final lookup =
          AtLookupImpl(atSign, rootDomain, TestUtils.rootServerPort);
      try {
        final challenge = (await lookup.executeCommand('from:$atSign\n'))!
            .trim()
            .replaceFirst(RegExp(r'^data:'), '');

        final chops = AtChopsImpl(AtChopsKeys.create(
          AtEncryptionKeyPair.create(
              enrolled.keys.defaultEncryptionPublicKey!.toString(), ''),
          AtPkamKeyPair.create(enrolled.keys.apkamPublicKey!.toString(),
              enrolled.keys.apkamPrivateKey!.toString()),
        ));

        // Always RSA — this is the enrollment's actual key, and the record says
        // so. Only the claim below varies.
        final signature = chops
            .sign(AtSigningInput(challenge)
              ..signingAlgoType = SigningAlgoType.rsa2048
              ..hashingAlgoType = HashingAlgoType.sha256
              ..signingMode = AtSigningMode.pkam)
            .result;

        final command = (PkamVerbBuilder()
              ..signingAlgo = claimedAlgo
              ..hashingAlgo = HashingAlgoType.sha256.name
              ..enrollmentlId = enrolled.enrollmentId
              ..signature = signature)
            .buildCommand();

        expect(command, contains('signingAlgo:$claimedAlgo'),
            reason: 'the built command must carry the claimed algorithm, or '
                'this test varies nothing');

        return await lookup.executeCommand(command);
      } finally {
        await lookup.close();
      }
    }

    // Control: the truthful claim authenticates, so the machinery works and a
    // failure in the second arm would mean something.
    expect(await authenticateClaiming('rsa2048'), contains('success'),
        reason: 'the enrollment is approved and the signature is genuine, so '
            'a truthful claim must authenticate');

    // The assertion: succeeding here is the property, the atServer having
    // verified with the algorithm the RECORD names and ignored a wire field
    // that said something else.
    expect(await authenticateClaiming('mldsa65'), contains('success'),
        reason: 'the atServer must verify against the enrollment record\'s '
            'signingAlgo and treat the wire field as a claim. If this fails, '
            'the verifier is chosen by the caller — and a caller that chooses '
            'the verifier chooses whether its signature is checked at all');
  });
}
