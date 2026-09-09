// The key-package surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

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

/// A second host running against a copy of an enrollment's keyfile.
///
/// A copy is not a second enrollment: both hosts share one APKAM keypair and
/// one key package, so a secret sealed once opens on both and one revoke cuts
/// both.
void main() {
  TestUtils.isolateStorage('copied_keyfile_test');
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo,
            posture: legacyPlusPqProviders);
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
        // pq is the key exchange; the enrollment still authenticates with an
        // RSA-2048 APKAM keypair.
        signingAlgo: SigningAlgoType.rsa2048,
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

    // The copy: serialize and re-read, exactly as copying the file does. The
    // atsign is set first because the in-flight AtKeys handed to
    // metadataBuilder carries none, while a .atKeys file on disk always does.
    originalKeys!.atsign ??= atSign.toAtsign();
    final copiedKeys = AtKeys.fromJson(originalKeys!.toJson());

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

    expect(copiedMaterial!.bytes.bytes, originalMaterial.bytes.bytes,
        reason: 'the copy must hold the same KEM private half, or "one '
            'recipient" is true of the advertisement and false of what can '
            'actually be opened');

    // Same APKAM keypair, so the same enrollment — one enrollment id is all an
    // operator has to revoke.
    expect(copiedKeys.apkamPublicKey!.toString(),
        originalKeys!.apkamPublicKey!.toString());
    expect(copiedKeys.apkamPrivateKey!.toString(),
        originalKeys!.apkamPrivateKey!.toString());

    // On the wire rather than by comparing strings: the copy authenticates as
    // that same enrollment against the live atServer.
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

    // Revoking the one enrollment cuts the copy too; the authentication above
    // is this arm's control — the same keyfile over a connection built the
    // same way, refused only after the revoke.
    final revoked = await atClient.enrollmentService!.revoke(
        EnrollmentRequestDecision.revoked(response.enrollmentId, atSign));
    // NOTE: assert the acknowledgement — a `data:` response naming another
    // enrollment or status does not throw, and "the copy is refused" below
    // would then be equally explained by the revoke never having taken.
    expect(revoked.enrollmentId, response.enrollmentId);
    expect(revoked.enrollStatus, EnrollmentStatus.revoked);

    final afterRevoke =
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort)
          ..enrollmentId = response.enrollmentId
          ..atChops = AtChopsImpl(AtChopsKeys.create(
            AtEncryptionKeyPair.create(
                copiedKeys.defaultEncryptionPublicKey!.toString(), ''),
            AtPkamKeyPair.create(copiedKeys.apkamPublicKey!.toString(),
                copiedKeys.apkamPrivateKey!.toString()),
          ));
    try {
      // NOTE: named rather than `throwsA(anything)` — on a live connection a
      // reset, a timeout or a malformed command throws too, so only the
      // atServer's `AT0027 … is revoked` may pass this arm.
      await expectLater(
          afterRevoke.pkamAuthenticate(enrollmentId: response.enrollmentId),
          throwsA(predicate(
              (e) => '$e'.contains('AT0027') && '$e'.contains('is revoked'))),
          reason: 'revocation is per-enrollment, so one revoke cuts every '
              'host sharing the copy at once. The keypair in the copied file '
              'is untouched and was accepted moments ago — what changed is '
              'the enrollment record it authenticates against');
    } finally {
      await afterRevoke.close();
    }
  });
}
