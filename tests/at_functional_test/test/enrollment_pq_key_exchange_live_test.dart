// The substrate is deliberately marked @experimental; exercising it from
// another package is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert' show base64Decode;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show AESKey;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/secret_sharing/envelope_addressing.dart'
    show EnvelopeAddressing;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrollment_approval.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// The reversed enrollment key exchange against a live atServer — UC-A2.1.
///
/// Under `EnrollmentKeyExchangeMode.pq` the enrollee generates no symmetric
/// key: the approver mints it and seals it to the advertised key package, so
/// nothing RSA-wrapped rides the request.
void main() {
  TestUtils.isolateStorage('enrollment_pq_key_exchange_live_test');
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace,
        posture: legacyPlusPqProviders);
    atClient = manager.atClient;
  });

  /// Submits a real `enroll:request` in pq mode and returns what the enrolling
  /// side keeps: its enrollment id, the kpid it advertised, the `AtKeys`
  /// holding the key package's private half, and the response to wait on.
  Future<
      ({
        String enrollmentId,
        String kpid,
        AtKeys keys,
        AtEnrollmentResponse response
      })> enrolAsPq() async {
    final otp = (await atClient.getOTP()).response;

    Map<String, dynamic>? built;
    AtKeys? enrolleeKeys;
    final build = enrollmentKeyPackageBuilder(atSign);

    final request = AtEnrollmentRequest.pq(
      session: TestUtils.enrollmentSession(atSign),
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
      // UC-A2.1 is about the key exchange; which algorithm authenticates the
      // connection is a separate axis.
      signingAlgo: SigningAlgoType.rsa2048,
    );

    final response = await AtEnrollment.create().submit(
      request,
      TestUtils.unauthenticatedLookUp(atSign),
    );
    expect(response.enrollStatus, EnrollmentStatus.pending);

    final payload =
        SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
    return (
      enrollmentId: response.enrollmentId,
      kpid: ((payload['keys'] as List).single as Map)['kid'] as String,
      keys: enrolleeKeys!,
      response: response,
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
    // NOTE: every pq approval seals from the approver's own key package, so it
    // must hold one.
    await AtClientSecretSharing.forClient(atClient).register();

    final enrolled = await enrolAsPq();

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: enrolled.enrollmentId,
      // What an approving app passes on the legacy path: the record says this
      // enrollment sent no key, so at_client mints one and ignores this.
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    // NOTE: resolved over the new enrollment's own connection, because only
    // that side shows the atServer letting a connection scoped to the granted
    // namespace scan for and read the key.
    final enrolleeLookup =
        TestUtils.lookUpAs(atSign, enrolled.keys,
        enrollmentId: enrolled.enrollmentId);

    expect(
        await enrolleeLookup.pkamAuthenticate(
            enrollmentId: enrolled.enrollmentId),
        true,
        reason: 'the enrollment is approved, so its APKAM keypair must '
            'authenticate before it can collect anything');

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: Duration(seconds: 20));
    final symmetricKey = await resolve(enrolled.keys, enrolleeLookup).first;

    expect(symmetricKey, isNotEmpty,
        reason: 'without this the enrollment authenticates and then cannot '
            'unwrap its own encryption private key');
    expect(base64Decode(symmetricKey).length, 32,
        reason: 'an AES-256 key, which is what the encryption private key and '
            'the self-encryption key were wrapped under');
  });

  test(
      'a key conveyed by an approval that did not land leaves the enrollee '
      'able to complete', () async {
    final sharing = AtClientSecretSharing.forClient(atClient);
    await sharing.register();
    final enrolled = await enrolAsPq();

    // NOTE: what a stop between conveying the minted key and approving leaves
    // behind: a key conveyed to the package that no approval encrypted under.
    final record = (await atClient.enrollmentService!.fetchEnrollmentRequests())
        .firstWhere((e) => e.enrollmentId == enrolled.enrollmentId);
    final leftOver = AESKey.generate(32).key;
    await sharing.shareSecretWith(
        KeyPackage.fromPayload(
            SignedEnvelope.fromJson(record.metadata!['keyPackage'] as Map)
                .payload,
            enrollmentId: enrolled.enrollmentId),
        Secret(
            namespace: namespace,
            name: enrollmentApkamSymmetricKeySecretName,
            value: leftOver),
        inReplyTo: EnvelopeAddressing.unsolicited);

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: enrolled.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));
    await awaitEnrollmentApproval(enrolled.response,
        atSign: atSign, rootDomain: TestUtils.rootDomain);

    final keys = await enrolled.response.session!.atKeysIo.read(atSign);
    expect(keys.enrollmentSymmetricKey?.key, isNot(leftOver),
        reason: 'the left-over key decrypts nothing the approval encrypted');
    expect(keys.encryptionKeyPair, isNotNull,
        reason: 'the enrollee kept the key the approval encrypted under, '
            'whichever order the two envelopes were found in');
  });
}
