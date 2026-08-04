// The substrate and the chain are deliberately marked @experimental and will
// be reshaped as the group surface matures.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

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

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, namespace);
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

    final link = await sharing.wrapAndSign(PqSigningChain.linkPayload(
      childEnrollmentId: enrollmentId,
      childApkamPublicKey: before.value as String,
    ));

    await PqSigningChain.publishLink(atClient, enrollmentId, link);

    final after = await atClient.get(AtKey.fromString(uri),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);

    expect(after.value, before.value,
        reason: 'the link is additive metadata, and the value is the signing '
            'key every verifier on this atSign resolves — a write that '
            'disturbed it would break every signature check at once');

    final read = await PqSigningChain.readLink(atClient, enrollmentId);
    expect(read, isNotNull,
        reason: 'this is the property the whole parent-signs/child-publishes '
            'arrangement is built on: appMetadata a client adds to _apsk '
            'has to survive on the atServer');
    expect(read!['signature'], link['signature']);
  });

  test('a live published link verifies against the key it names', () async {
    final sharing = AtClientSecretSharing.forClient(atClient);
    final read =
        await PqSigningChain.readLink(atClient, sharing.enrollmentId);

    await expectLater(
        sharing.verifyEnvelopeSignature(read!, signerAtSign: atSign),
        completes,
        reason: 'verification resolves the signer\'s _apsk from the atServer, '
            'so this exercises the published record rather than an in-memory '
            'copy of it');
  });

  test('an atSign anchors itself to its own signing root, and the walk sees it',
      () async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());

    // Mints if this run's atServer has no root yet, and anchors this
    // enrollment either way on the next call below.
    await PqSigningRoot(atClient, keysIo: io)
        .mintIfAbsent(isFullyPrivileged: true);

    final sharing = AtClientSecretSharing.forClient(atClient);
    await PqSigningChain.publishOwnRootLink(atClient,
        isFullyPrivileged: () async => true, keysIo: io);

    final link =
        await PqSigningChain.readRootLink(atClient, sharing.enrollmentId);
    expect(link, isNotNull,
        reason: 'the anchor is metadata on a public record the atServer also '
            'writes, so that it survives is the property worth watching '
            'rather than assuming');

    final result = await PqSigningChain.verifyChain(
        atClient, sharing, sharing.enrollmentId);

    expect(result.verdict, ChainVerdict.anchored,
        reason: 'the walk fetches the published root and checks the ML-DSA '
            'signature against it, so this exercises the real record rather '
            'than an in-memory copy. Reason if not: ${result.reason}');
  });

  test('approving conveys a chain link alongside the symmetric key', () async {
    final otp = (await atClient.getOTP()).response;

    Map<String, dynamic>? built;
    final build = enrollmentKeyPackageBuilder(atSign);

    final request = AtEnrollmentRequest(
      atSign: atSign,
      appName: namespace,
      deviceName: 'chain-${Uuid().v4().hashCode}',
      namespaces: {namespace: 'rw'},
      otp: otp,
      keyExchangeMode: EnrollmentKeyExchangeMode.pq,
      metadataBuilder: (keysIo) async => built = await build(keysIo),
      apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
    );

    final response = await AtEnrollment.create().submit(
      request,
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );
    final payload = (built!['keyPackage'] as Map)['payload'] as Map;
    final kpid = ((payload['keys'] as List).single as Map)['kid'] as String;

    await atClient.enrollmentService!.approve(
        EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: response.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    // Two envelopes are addressed to this key package: the symmetric key it
    // cannot start without, and the chain link vouching for it. Counted rather
    // than read, because both are sealed to a private half only the enrolling
    // device holds — the count is what an approver-side test can honestly see.
    final envelopes = await atClient.getAtKeys(
        regex: '.*\\.$kpid\\.__ssenv\\..*', useRemoteAtServer: true);

    expect(envelopes.length, greaterThanOrEqualTo(2),
        reason: 'approval conveys the symmetric key and the chain link; only '
            'one of them arriving would leave the new device either unable to '
            'decrypt or permanently unsigned');
  });
}
