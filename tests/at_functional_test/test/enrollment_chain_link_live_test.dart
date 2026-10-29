@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;

import 'test_utils.dart';

/// The atSign's signing root against a live atServer: who mints it, and who
/// is given its private.
void main() {
  TestUtils.isolateStorage('enrollment_chain_link_live_test');
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  late InMemoryAtKeysIo keysIo;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // NOTE: the approver conveys the root private out of `atClient.atKeysIo`,
    // so a client built without one has nothing to convey.
    keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
    atClient = manager.atClient;
    await AtClientSecretSharing.forClient(atClient).register();
  });

  test(
      'a fully privileged client mints the signing root when none is '
      'published', () async {
    // NOTE: mints into the AtKeysIo the client itself holds, so the approval
    // rows below find a private to convey.
    await PqSigningRoot(atClient, keysIo: keysIo)
        .mintIfAbsent(isFullyPrivileged: true);

    expect(await PqSigningRoot.publishedPublicKey(atClient, atSign), isNotNull);
    expect(await PqSigningRoot(atClient, keysIo: keysIo).privateHalf(atSign),
        isNotNull,
        reason: 'a published root whose private this client did not keep '
            'would have nothing to convey or to link with');
  });

  test('the enrollment that loses the race does not mint a second root',
      () async {
    // NOTE: this row belongs beside the one above, which mints the root on
    // this atSign into a keyfile it keeps — that is what makes the loser's
    // precondition hold by construction rather than by seeding a root whose
    // private nobody holds.
    final published = await PqSigningRoot.publishedPublicKey(atClient, atSign);
    expect(published, isNotNull,
        reason: 'the row above minted it, so this call is the LOSER by '
            'construction — that is the case under test');

    final loserKeys = InMemoryAtKeysIo();
    await loserKeys.write(atSign, AtKeys());
    final loser = PqSigningRoot(atClient, keysIo: loserKeys);

    expect(await loser.mintIfAbsent(isFullyPrivileged: true), isNull,
        reason: 'a non-null return here says "I published the root", and its '
            'caller would anchor every later signature to a key the atSign '
            'never accepted');
    expect(await PqSigningRoot.publishedPublicKey(atClient, atSign), published,
        reason: 'and it must not have disturbed the published record — now a '
            'property of the client\'s own check rather than of the atServer '
            'refusing the write');
    expect(await loser.privateHalf(atSign), isNull,
        reason: 'the loser must hold nothing afterwards: an active private '
            'here would satisfy the pull\'s "already holding it" guard, and '
            'the one heal a loser has — being given the real private by a '
            'holder — would never fire');

    // A namespace-scoped enrollment must not even attempt it — the root
    // vouches for every enrollment, so minting it is not a scoped operation.
    expect(await loser.mintIfAbsent(isFullyPrivileged: false), isNull);
  });

  /// Enrols and approves with [namespaces], returning the kpid it advertised
  /// and the number of envelopes sealed to it.
  Future<({String kpid, int envelopes, Map<String, dynamic>? granted})>
      enrolApproveAndCount(Map<String, String> namespaces) async {
    final otp = (await atClient.getOTP()).response;
    Map<String, dynamic>? built;
    final build = enrollmentKeyPackageBuilder(atSign,
        signingAlgo: SigningAlgoType.mldsa65);

    final response = await AtEnrollment.create().submit(
      AtEnrollmentRequest.pq(
        session: TestUtils.enrollmentSession(atSign),
        appName: namespace,
        deviceName: 'priv-${Uuid().v4().hashCode}',
        namespaces: namespaces,
        otp: otp,
        // pq mode so the approver mints the symmetric key rather than
        // RSA-decrypting one that no enrollee is running to have produced.
        metadataBuilder: (keysIo) async => built = await build(keysIo),
        apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
        // NOTE: at_auth refuses rsa2048 with the pq exchange.
        signingAlgo: SigningAlgoType.mldsa65,
      ),
      TestUtils.unauthenticatedLookUp(atSign),
    );

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: response.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    final payload =
        SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
    final kpid = ((payload['keys'] as List).single as Map)['kid'] as String;
    final granted =
        (await atClient.enrollmentService!.fetchEnrollmentRequests())
            .where((e) => e.enrollmentId == response.enrollmentId)
            .firstOrNull
            ?.namespace;
    final envelopes = await atClient.getAtKeys(
        regex: '.*\\.$kpid\\.__ssenv\\..*', useRemoteAtServer: true);
    return (kpid: kpid, envelopes: envelopes.length, granted: granted);
  }

  test('the root private reaches a privileged enrollment and no other',
      () async {
    final privileged = await enrolApproveAndCount(
        {'*': 'rw', '__manage': 'rw', namespace: 'rw'});
    final scoped = await enrolApproveAndCount({namespace: 'rw'});

    expect(EnrollmentServiceImpl.isFullyPrivileged(privileged.granted), isTrue,
        reason: 'the atServer has to have granted * and __manage for this to '
            'be a test of the privilege gate at all');
    expect(EnrollmentServiceImpl.isFullyPrivileged(scoped.granted), isFalse);

    expect(privileged.envelopes, scoped.envelopes + 1,
        reason: 'the root vouches for every enrollment on the atSign, so only '
            'the fully privileged class receives its private — and the '
            'approver held one throughout, so the difference is the gate '
            'rather than there having been nothing to send');
  });
}
