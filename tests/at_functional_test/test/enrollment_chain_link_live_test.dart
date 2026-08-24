// The substrate and the chain are deliberately marked @experimental and will
// be reshaped as the group surface matures.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;

import 'test_utils.dart';

/// The approval chain against a live atServer.
///
/// The design rests on a property of the atServer that was established by
/// reading its code and never observed: `_apsk` is written at first-enrollment
/// creation and on approve, and *not* on every authenticated use, so metadata
/// a client adds afterwards survives. The whole parent-signs / child-publishes
/// arrangement exists because of that, so it is worth watching happen rather
/// than trusting a code read — the same class of cross-tier assumption that
/// has already been wrong twice on this branch.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  late InMemoryAtKeysIo keysIo;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    // The approver conveys the root private out of `atClient.atKeysIo`, so a
    // client built without one could never hold it and any assertion about
    // conveyance would be about the harness rather than the code.
    keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    atClient = manager.atClient;
    await AtClientSecretSharing.forClient(atClient).register();
  });

  test('a link written onto a live _apsk survives, and the key with it',
      () async {
    final sharing = AtClientSecretSharing.forClient(atClient);
    final enrollmentId = sharing.enrollmentId;
    final uri = PqSigningChain.apskUri(atSign, enrollmentId);

    final before = await atClient.get(AtKey.fromString(uri),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);

    final link = await sharing.wrapAndSign(
      PqSigningChain.linkPayload(
        childEnrollmentId: enrollmentId,
        childApkamPublicKey: before.value as String,
      ),
      // Typed as a link because that is what is being published. Signed as
      // anything else it is not one, which is the whole point of the type —
      // and the file publishes it by hand rather than through signLinkFor,
      // so nothing else here would have said so.
      type: EnvelopeType.chainLink,
    );

    await PqSigningChain(atClient).publishLink(enrollmentId, link);

    final after = await atClient.get(AtKey.fromString(uri),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);

    expect(after.value, before.value,
        reason: 'the link is additive metadata, and the value is the signing '
            'key every verifier on this atSign resolves — a write that '
            'disturbed it would break every signature check at once');

    final read = await PqSigningChain(atClient).readLink(enrollmentId);
    expect(read, isNotNull,
        reason: 'this is the property the whole parent-signs/child-publishes '
            'arrangement is built on: appMetadata a client adds to _apsk '
            'has to survive on the atServer');
    expect(read, link,
        reason: 'the link read back is the one published, byte for byte');
  });

  test('a live published link verifies against the key it names', () async {
    final sharing = AtClientSecretSharing.forClient(atClient);
    final read =
        await PqSigningChain(atClient).readLink(sharing.enrollmentId);

    await expectLater(
        sharing.verifyEnvelopeSignature(read!,
            signerAtSign: atSign, expecting: EnvelopeType.chainLink),
        completes,
        reason: 'verification resolves the signer\'s _apsk from the atServer, '
            'so this exercises the published record rather than an in-memory '
            'copy of it');
  });

  test('an atSign anchors itself to its own signing root, and the walk sees it',
      () async {
    // Mints if this run's atServer has no root yet, into the very AtKeysIo the
    // client holds — so the approval tests below find a private to convey.
    await PqSigningRoot(atClient, keysIo: keysIo)
        .mintIfAbsent(isFullyPrivileged: true);

    final sharing = AtClientSecretSharing.forClient(atClient);
    await PqSigningChain(atClient)
        .publishOwnRootLink(isFullyPrivileged: () async => true, keysIo: keysIo);

    final link =
        await PqSigningChain(atClient).readRootLink(sharing.enrollmentId);
    expect(link, isNotNull,
        reason: 'the anchor is metadata on a public record the atServer also '
            'writes, so that it survives is the property worth watching '
            'rather than assuming');

    final result = await PqSigningChain(atClient).verifyChain(
        sharing, sharing.enrollmentId);

    expect(result.verdict, ChainVerdict.anchored,
        reason: 'the walk fetches the published root and checks the ML-DSA '
            'signature against it, so this exercises the real record rather '
            'than an in-memory copy. Reason if not: ${result.reason}');
  });

  test('the enrollment that loses the race does not mint a second root',
      () async {
    // Here rather than in `pq_signing_root_mint_lock_test.dart` because this
    // file is the one that legitimately mints the root on this atSign — the
    // row above does it, into a keyfile it keeps — so the precondition is
    // established by construction rather than by seeding a root whose private
    // nobody holds. A file that seeded one took three rows of THIS file down
    // on 2026-08-15, which is why the row lives here now.
    //
    // What a losing CLIENT does is the half the atServer cannot show: it must
    // return empty-handed AND hold nothing, so its caller knows to request the
    // root from a holder. With the record mutable, a loser that minted anyway
    // would OVERWRITE the winner's root rather than be refused — which is the
    // outcome the whole interlock exists to prevent — and one that kept a
    // filed private would read as "already holding the root" forever and
    // never ask.
    //
    // Against an atSign whose root is already published the loss is met at the
    // absence check: nothing reaches the atServer and nothing is filed. The
    // narrower race, where two mints both find the record absent and one is
    // refused the lock, is unit-covered; the refusal itself is what
    // `pq_signing_root_mint_lock_test.dart` watches the live atServer issue.
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
    final build = enrollmentKeyPackageBuilder(atSign);

    final response = await AtEnrollment.create().submit(
      AtEnrollmentRequest.pq(
        atSign: atSign,
        appName: namespace,
        deviceName: 'priv-${Uuid().v4().hashCode}',
        namespaces: namespaces,
        otp: otp,
        // pq mode so the approver mints the symmetric key. On the legacy path
        // it would RSA-decrypt whatever the decision carries, and this test has
        // no enrollee running to have produced one.
        metadataBuilder: (keysIo) async => built = await build(keysIo),
        apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
        // pq is the key exchange; the enrollment still authenticates with
        // an RSA-2048 APKAM keypair. What is under test is the privilege
        // gate on the chain link, not the signing algorithm.
        signingAlgo: SigningAlgoType.rsa2048,
      ),
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );

    await atClient.enrollmentService!.approve(
        EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: response.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    final payload = SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
    final kpid = ((payload['keys'] as List).single as Map)['kid'] as String;
    final granted = (await atClient.enrollmentService!.fetchEnrollmentRequests())
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

    // Checked, not assumed: if the atServer trimmed the grant, the approver
    // would classify it as scoped and the comparison below would be between
    // two identical cases while still reading green.
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

  test('approving conveys a link alongside the symmetric key', () async {
    final otp = (await atClient.getOTP()).response;

    Map<String, dynamic>? built;
    final build = enrollmentKeyPackageBuilder(atSign);

    final request = AtEnrollmentRequest.pq(
      atSign: atSign,
      appName: namespace,
      deviceName: 'chain-${Uuid().v4().hashCode}',
      namespaces: {namespace: 'rw'},
      otp: otp,
      metadataBuilder: (keysIo) async => built = await build(keysIo),
      apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
      // As above: pq key exchange, RSA-2048 APKAM authentication.
      signingAlgo: SigningAlgoType.rsa2048,
    );

    final response = await AtEnrollment.create().submit(
      request,
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );
    final payload = SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
    final kpid = ((payload['keys'] as List).single as Map)['kid'] as String;

    await atClient.enrollmentService!.approve(
        EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: response.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    // Two envelopes are addressed to this key package: the symmetric key it
    // cannot start without, and the link vouching for it — root-flavoured
    // here, because this approver authenticates with the atSign's own keys
    // and is fully privileged. Counted rather than read, because both are
    // sealed to a private half only the enrolling device holds — the count
    // is what an approver-side test can honestly see.
    final envelopes = await atClient.getAtKeys(
        regex: '.*\\.$kpid\\.__ssenv\\..*', useRemoteAtServer: true);

    expect(envelopes.length, greaterThanOrEqualTo(2),
        reason: 'approval conveys the symmetric key and the link; only one '
            'of them arriving would leave the new device either unable to '
            'decrypt or permanently unsigned');
  });
}
