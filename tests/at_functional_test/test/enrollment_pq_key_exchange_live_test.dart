// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures. Exercising it from another package is the point
// of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert' show base64Decode;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show
        AtChopsImpl,
        AtChopsKeys,
        AtEncryptionKeyPair,
        AtPkamKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
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

    final request = AtEnrollmentRequest.pq(
      atSign: atSign,
      appName: namespace,
      deviceName: 'pq-${Uuid().v4().hashCode}',
      namespaces: {namespace: 'rw'},
      otp: otp,
      metadataBuilder: (keysIo) async {
        built = await build(keysIo);
        enrolleeKeys = await keysIo.read(atSign);
        return built;
      },
      apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
      // UC-A2.1 is about the key EXCHANGE — that nothing RSA-wrapped rides
      // the request. Which algorithm authenticates the connection is the
      // other axis, and this row asserts nothing about it.
      signingAlgo: SigningAlgoType.rsa2048,
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

    // Authenticate as the NEW enrollment and resolve over its own connection,
    // which is what waitForApproval does. Running this over the approver's
    // connection would prove the envelope is discoverable, authentic and
    // openable, but not the part that only the enrolling side can show: that
    // the atServer's namespace gating lets a connection scoped to
    // {buzz: rw} scan for and read a self key sitting in buzz. If it did not,
    // every pq enrollment would fail here in production while a test driven
    // from the approver stayed green.
    //
    // The chops are built from the APKAM keypair alone, deliberately. PKAM
    // needs nothing else, and this enrollment has nothing else — the symmetric
    // key is the thing it is about to fetch, and AtKeys.toAtChops reads its
    // absence as "PKAM keys" and then demands the encryption private key that
    // is equally not there yet.
    final enrolleeLookup = AtLookupImpl(
        atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort)
      ..enrollmentId = enrolled.enrollmentId
      ..atChops = AtChopsImpl(AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            enrolled.keys.defaultEncryptionPublicKey!.toString(), ''),
        AtPkamKeyPair.create(enrolled.keys.apkamPublicKey!.toString(),
            enrolled.keys.apkamPrivateKey!.toString()),
      ));

    expect(
        await enrolleeLookup.pkamAuthenticate(
            enrollmentId: enrolled.enrollmentId),
        true,
        reason: 'the enrollment is approved, so its APKAM keypair must '
            'authenticate before it can collect anything');

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: Duration(seconds: 20));
    final symmetricKey = await resolve(enrolled.keys, enrolleeLookup);

    expect(symmetricKey, isNotEmpty,
        reason: 'without this the enrollment authenticates and then cannot '
            'unwrap its own encryption private key');
    expect(base64Decode(symmetricKey).length, 32,
        reason: 'an AES-256 key, which is what the encryption private key and '
            'the self-encryption key were wrapped under');
  });
}
