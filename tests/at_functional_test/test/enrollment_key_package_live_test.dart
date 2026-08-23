// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// The whole key-package chain against a live atServer.
///
/// Every link has unit coverage, but each end was mocked against the other:
/// the builder's tests supply their own `AtKeys`, and the directory's tests
/// seed advertisements signed by an already-enrolled client. Nothing had ever
/// run the two together, which is exactly where the defects were — a package
/// stamped with an enrollment id its signer could not know would have been
/// refused by every verifier, and no unit test could see it.
///
/// So this drives the real thing: the package rides `enroll:request`, the
/// atServer stores it verbatim, the approver reads it back off the record it
/// is approving, verifies it against the `_apsk` the atServer publishes on
/// approval, and seals this atSign's secrets to it.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
    atClient = manager.atClient;
  });

  /// Submits a real `enroll:request` carrying a key package built by
  /// [enrollmentKeyPackageBuilder], and returns the enrollment id together
  /// with the kpid of the key it advertised.
  Future<({String enrollmentId, String kpid})> enrolWithKeyPackage() async {
    final otp = (await atClient.getOTP()).response;

    Map<String, dynamic>? built;
    final build = enrollmentKeyPackageBuilder(atSign);

    final request = AtEnrollmentRequest(
      atSign: atSign,
      appName: namespace,
      deviceName: 'kp-${Uuid().v4().hashCode}',
      namespaces: {namespace: 'rw'},
      otp: otp,
      metadataBuilder: (keysIo) async => built = await build(keysIo),
    );

    final response = await AtEnrollment.create().submit(
      request,
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );
    expect(response.enrollStatus, EnrollmentStatus.pending);

    final payload = SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
    return (
      enrollmentId: response.enrollmentId,
      kpid: ((payload['keys'] as List).single as Map)['kid'] as String,
    );
  }

  test('a key package survives enroll:request and comes back on the record',
      () async {
    final enrolled = await enrolWithKeyPackage();

    final request =
        (await atClient.enrollmentService!.fetchEnrollmentRequests())
            .firstWhere((e) => e.enrollmentId == enrolled.enrollmentId);

    expect(request.metadata?['keyPackage'], isNotNull,
        reason: 'the atServer stores enrollment metadata verbatim, and this is '
            'the only place it is ever written — so if it does not survive '
            'the request, there is no second chance to attach it');
  });

  test('approving seals this atSign\'s secrets to the advertised key package',
      () async {
    // Something worth conveying, in a namespace the new enrollment will hold.
    final sharing = AtClientSecretSharing.forClient(atClient);
    await sharing.register();
    await sharing.secretStore.putSecret(Secret(
      namespace: namespace,
      name: 'kp-e2e-${Uuid().v4().hashCode}',
      value: 'conveyed on approval',
    ));

    final enrolled = await enrolWithKeyPackage();
    final request =
        (await atClient.enrollmentService!.fetchEnrollmentRequests())
            .firstWhere((e) => e.enrollmentId == enrolled.enrollmentId);

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: enrolled.enrollmentId,
      apkamSymmetricKey:
          AtBytes.fromString(request.encryptedAPKAMSymmetricKey!),
    ));

    // The observable result: an envelope addressed to the kpid the enrolling
    // app advertised, sitting on the atServer for it to collect. Read remote
    // deliberately — a local-only check would pass with nothing having left
    // this device.
    final envelopes = await atClient.getAtKeys(
        regex: '.*\\.${enrolled.kpid}\\.__ssenv\\..*', useRemoteAtServer: true);

    expect(envelopes, isNotEmpty,
        reason: 'approving is when a new device gets the secrets it was just '
            'authorised for; without this it authenticates normally and '
            'decrypts nothing');
  });

  test(
      'the advertised package verifies against the _apsk the atServer '
      'publishes', () async {
    final enrolled = await enrolWithKeyPackage();
    final request =
        (await atClient.enrollmentService!.fetchEnrollmentRequests())
            .firstWhere((e) => e.enrollmentId == enrolled.enrollmentId);

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: enrolled.enrollmentId,
      apkamSymmetricKey:
          AtBytes.fromString(request.encryptedAPKAMSymmetricKey!),
    ));

    // _apsk exists only once the enrollment is approved, which is why
    // conveyance runs after the approval rather than before it.
    final (keyPackage, status) = await verifyAdvertisedKeyPackage(
      request.metadata!['keyPackage'],
      signer: AtClientEnvelopeSigner(atClient),
      signerAtSign: atSign,
      enrollmentId: enrolled.enrollmentId,
    );

    expect(status, KeyPackageStatus.present,
        reason: 'the package carries no enrollmentId claim — it was signed '
            'before the atServer assigned one — so this is the assertion that '
            'an absent claim verifies on the real wire');
    expect(keyPackage!.kpid, enrolled.kpid);
  });
}
