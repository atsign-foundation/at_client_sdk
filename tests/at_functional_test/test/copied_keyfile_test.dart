// The key-package surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show AtChopsImpl, AtChopsKeys, AtEncryptionKeyPair, AtPkamKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/secret_sharing/key_package_persistence.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// A second host running against a **copy** of an enrollment's keyfile.
///
/// This is the case people actually hit — a `.atKeys` file copied to a laptop,
/// a container image baked with one, a device restored from backup — and the
/// design's answer is that it is not a second enrollment at all. Both hosts
/// share one APKAM keypair and one key package, so they are one recipient: a
/// secret sealed once opens on both, and revoking the enrollment cuts both,
/// because there is only one thing to revoke.
///
/// That last part is why the identity assertions here matter more than they
/// look. If a copied keyfile somehow presented as a distinct recipient, an
/// operator revoking the enrollment they knew about would leave the copy
/// running, and nothing in the system would report a second holder.
///
/// The copy is made by round-tripping through `toJson`/`fromJson` rather than
/// by reusing the object, because that is what copying the file does — and a
/// test that passed the same instance twice would be asserting that a variable
/// equals itself.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    atClient = manager.atClient;
    // The approver seals the enrollee's symmetric key to its own key package,
    // so it has to have one registered before it can approve anything.
    await AtClientSecretSharing.forClient(atClient).register();
  });

  test('a copied keyfile is the same enrollment and the same recipient',
      () async {
    final otp = (await atClient.getOTP()).response;

    Map<String, dynamic>? built;
    AtKeys? originalKeys;
    final build = enrollmentKeyPackageBuilder(atSign);

    final response = await AtEnrollment.create().submit(
      AtEnrollmentRequest.pq(
        atSign: atSign,
        appName: namespace,
        deviceName: 'copied-${Uuid().v4().hashCode}',
        namespaces: {namespace: 'rw'},
        otp: otp,
        metadataBuilder: (keysIo) async {
          built = await build(keysIo);
          originalKeys = await keysIo.read(atSign);
          return built;
        },
        apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
      ),
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: response.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    final advertisedKpid = (((SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload
            as Map)['keys'] as List)
        .single as Map)['kid'] as String;

    // The copy: serialize and re-read, exactly as copying the file does.
    //
    // The atsign is set first because the in-flight AtKeys handed to
    // metadataBuilder does not carry one yet, while a .atKeys file on disk
    // always does — and it is the file that gets copied. Restoring it is
    // fidelity to the scenario, not a convenience.
    originalKeys!.atsign ??= atSign.toAtsign();
    final copiedKeys = AtKeys.fromJson(originalKeys!.toJson());

    // Same key package, so the same recipient. This is the assertion the rest
    // of the row rests on — anything sealed to that kpid is sealed to both
    // hosts at once, because there is only one kpid.
    final originalMaterial = keyPackageMaterial(originalKeys!);
    final copiedMaterial = keyPackageMaterial(copiedKeys);

    expect(originalMaterial, isNotNull,
        reason: 'the enrollment advertised a key package, so its private half '
            'must be in the keyfile; without it there is nothing to copy');
    expect(copiedMaterial?.keyId, originalMaterial!.keyId,
        reason: 'the copy must resolve to the SAME key package id. A distinct '
            'id would mean a copied keyfile is a second recipient that the '
            'atSign never approved and no operator can see');
    expect(copiedMaterial?.keyId, advertisedKpid,
        reason: 'and it must be the id the enrollment actually advertised, or '
            'this compares two local objects and tells us nothing about what '
            'senders will seal to');

    // Same APKAM keypair, so the same enrollment — which is what makes
    // revocation cover both hosts. There is one enrollment id, so an operator
    // revoking it cannot miss the copy.
    expect(copiedKeys.apkamPublicKey!.toString(),
        originalKeys!.apkamPublicKey!.toString());
    expect(copiedKeys.apkamPrivateKey!.toString(),
        originalKeys!.apkamPrivateKey!.toString());

    // Proven on the wire rather than by comparing strings: the copy
    // authenticates as that same enrollment against the live atServer.
    final copyLookup =
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort)
          ..enrollmentId = response.enrollmentId
          ..atChops = AtChopsImpl(AtChopsKeys.create(
            AtEncryptionKeyPair.create(
                copiedKeys.defaultEncryptionPublicKey!.toString(), ''),
            AtPkamKeyPair.create(copiedKeys.apkamPublicKey!.toString(),
                copiedKeys.apkamPrivateKey!.toString()),
          ));

    try {
      expect(
          await copyLookup.pkamAuthenticate(
              enrollmentId: response.enrollmentId),
          true,
          reason: 'the second host authenticates as the SAME enrollment id. '
              'Two hosts, one enrollment, one revocable thing — which is the '
              'whole claim');
    } finally {
      await copyLookup.close();
    }
  });
}
