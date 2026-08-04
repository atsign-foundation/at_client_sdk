// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file.
// ignore_for_file: experimental_member_use

import 'dart:convert' show base64Decode;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// The reversed enrollment key exchange against a live atServer.
///
/// UC-A2.1 asks that nothing in the conveyance path be RSA-wrapped, and the
/// enrollment symmetric key was the last thing that was: the enrollee
/// generated it and encrypted it to the atSign's long-lived RSA encryption
/// public key, and everything else the enrollment receives is wrapped under
/// it. Under `EnrollmentKeyExchangeMode.pq` the enrollee generates nothing and
/// the approver mints the key and seals it to the advertised key package.
///
/// This has to run live. Both halves are unit-covered, but the mandatory-field
/// check that made the reversal impossible lives in the atServer, not in
/// either client — a mocked atServer accepts a request that the real one
/// rejects outright, so nothing short of a live request proves the wire.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
    atClient = manager.atClient;
  });

  /// Submits a real `enroll:request` in pq mode and returns what the enrolling
  /// side keeps: its enrollment id, the kpid it advertised, and the `AtKeys`
  /// holding the key package's private half.
  Future<({String enrollmentId, String kpid, AtKeys keys})> enrolAsPq() async {
    final otp = (await atClient.getOTP()).response;

    Map<String, dynamic>? built;
    AtKeys? enrolleeKeys;
    final build = enrollmentKeyPackageBuilder(atSign);

    final request = AtEnrollmentRequest(
      atSign: atSign,
      appName: namespace,
      deviceName: 'pq-${Uuid().v4().hashCode}',
      namespaces: {namespace: 'rw'},
      otp: otp,
      keyExchangeMode: EnrollmentKeyExchangeMode.pq,
      metadataBuilder: (keysIo) async {
        built = await build(keysIo);
        enrolleeKeys = await keysIo.read(atSign);
        return built;
      },
      apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
    );

    final response = await AtEnrollment.create().submit(
      request,
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );
    expect(response.enrollStatus, EnrollmentStatus.pending);

    final payload = (built!['keyPackage'] as Map)['payload'] as Map;
    return (
      enrollmentId: response.enrollmentId,
      kpid: ((payload['keys'] as List).single as Map)['kid'] as String,
      keys: enrolleeKeys!,
    );
  }

  test('a pq enrollment reaches the atServer with no RSA-wrapped key',
      () async {
    final enrolled = await enrolAsPq();

    final record = (await atClient.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == enrolled.enrollmentId);

    expect(record.encryptedAPKAMSymmetricKey, anyOf(isNull, isEmpty),
        reason: 'this is the assertion UC-A2.1 actually makes: the request '
            'carried no symmetric key wrapped to a long-lived RSA key, so an '
            'adversary recording it has nothing to harvest. The published '
            'atServer rejects this request outright, which is why the check '
            'has to be live');
    expect(record.metadata?['keyPackage'], isNotNull,
        reason: 'and the package the approver encapsulates to did survive');
  });

  test('approving mints a symmetric key the enrollee can recover', () async {
    // The approver seals from its own key package, so it must hold one. This
    // is a new precondition for approval: before the reversal an approver with
    // no secrets to convey never reached sendEnvelope at all, and now every pq
    // approval does.
    await AtClientSecretSharing.forClient(atClient).register();

    final enrolled = await enrolAsPq();

    await atClient.enrollmentService!.approve(
        EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: enrolled.enrollmentId,
      // What an approving app would pass on the legacy path. The record says
      // this enrollment sent none, so at_client must mint one and ignore this
      // rather than trusting the caller.
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    // Drive the enrollee's own resolver — the code waitForApproval runs once
    // PKAM succeeds. It scans for the envelope, verifies its APKAM signature
    // against the _apsk the atServer published on approval, and opens it with
    // the key package private half minted before the request was sent.
    //
    // Run over the approver's authenticated connection rather than a second
    // PKAM session: this proves the envelope is discoverable, authentic and
    // openable by the key package. What it does not prove is the atServer's
    // namespace gating letting the *enrolling* connection read it, which
    // needs a test that authenticates as the new enrollment.
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: Duration(seconds: 20));
    final symmetricKey = await resolve(
        enrolled.keys, atClient.getRemoteSecondary()!.atLookUp);

    expect(symmetricKey, isNotEmpty,
        reason: 'without this the enrollment authenticates and then cannot '
            'unwrap its own encryption private key');
    expect(base64Decode(symmetricKey).length, 32,
        reason: 'an AES-256 key, which is what the encryption private key and '
            'the self-encryption key were wrapped under');
  });
}
