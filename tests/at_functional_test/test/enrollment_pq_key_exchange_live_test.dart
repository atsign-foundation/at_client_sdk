// The substrate is deliberately marked @experimental; exercising it from
// another package is the point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert' show base64Decode;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show AtChopsImpl, AtChopsKeys, AtEncryptionKeyPair, AtPkamKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
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
      // UC-A2.1 is about the key exchange; which algorithm authenticates the
      // connection is a separate axis.
      signingAlgo: SigningAlgoType.rsa2048,
    );

    final response = await AtEnrollment.create().submit(
      request,
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );
    expect(response.enrollStatus, EnrollmentStatus.pending);

    final payload =
        SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
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
    // namespace scan for and read the key. Its chops come from the APKAM
    // keypair alone — `AtKeys.toAtChops` would demand an encryption private
    // key this enrollment does not hold yet.
    final enrolleeLookup =
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort)
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
