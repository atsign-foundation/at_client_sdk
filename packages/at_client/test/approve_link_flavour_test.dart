// ignore_for_file: experimental_member_use

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart'
    show EnrollmentPrivilegeResolver;
import 'package:at_client/src/service/envelope_enrollment_conveyance.dart';
import 'package:at_commons/at_builders.dart' show EnrollVerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/enroll_link_fake.dart';
import 'test_utils/link_fixtures.dart';
import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';
import 'test_utils/test_keypairs.dart';

class _FakePrivilege implements EnrollmentPrivilegeResolver {
  _FakePrivilege(this.answer);
  final bool answer;

  @override
  Future<bool> isFullyPrivileged() async => answer;

  @override
  Future<bool> isEnrollmentFullyPrivileged(String enrollmentId) async => answer;
}

/// An approver links each key of the enrollment it approves, straight after
/// approving, through `enroll:link`.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-G3.5.
void main() {
  const atSign = '@alice';
  const enrolleeId = 'scoped-1';
  const namespace = 'buzz';
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMetadata;
  late List<EnrollVerbBuilder> linkCalls;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
    linkCalls = [];
  });

  MockAtClient buildMockClient(String enrollmentId,
      {EnrollLinkSupport enrollLink = EnrollLinkSupport.supported}) {
    final atClient = buildRemoteBackedMockClient(
        atSign: atSign,
        enrollmentId: enrollmentId,
        remoteData: remoteData,
        remoteMetadata: remoteMetadata,
        enrollLink: enrollLink,
        enrollLinkLog: linkCalls);
    when(() => atClient.getAtKeys(
        regex: any(named: 'regex'),
        showHiddenKeys: any(named: 'showHiddenKeys'),
        useRemoteAtServer: any(named: 'useRemoteAtServer'))).thenAnswer((inv) {
      final regex = RegExp(inv.namedArguments[#regex] as String);
      return Future.value(remoteData.keys
          .where((k) => regex.hasMatch(k))
          .map(AtKey.fromString)
          .toList());
    });
    when(() => atClient.delete(any())).thenAnswer((inv) {
      remoteData.remove('${inv.positionalArguments[0]}');
      return Future.value(true);
    });
    return atClient;
  }

  /// A registered enrollee listing K1 and K2, and the [Enrollment] record its
  /// approval reads; [keyPackage] false leaves the record without one.
  Future<(AtClientSecretSharing, Enrollment)> enrolleeWithTwoKeys(
      {bool keyPackage = true}) async {
    final enrolleeClient = buildMockClient(enrolleeId);
    await withSigningKey(enrolleeClient);
    await withSigningKey(enrolleeClient, alg: SigningAlgoType.mldsa65);
    final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
    await enrollee.register();
    final enrollment = Enrollment()
      ..enrollmentId = enrolleeId
      ..namespace = {namespace: 'rw'}
      ..apkamPublicKey =
          pkamKeyPairFor(atSign, enrolleeId).atPublicKey.publicKey;
    if (keyPackage) {
      enrollment.metadata = {
        'keyPackage': (await enrollee.signedKeyPackagePayload()).toJson()
      };
    }
    return (enrollee, enrollment);
  }

  EnvelopeEnrollmentConveyance conveyanceFor(MockAtClient approver,
          {required bool privileged}) =>
      EnvelopeEnrollmentConveyance(approver,
          listEnrollments: ({enrollmentListParams}) async => [],
          privilege: _FakePrivilege(privileged));

  Future<ApskRecord> record(AtClient c, String id) async =>
      (await PqSigningChain(c).readRecord(id))!;

  /// An approver whose own client data signing key carries a root link, and
  /// which does not hold the root.
  Future<MockAtClient> approverWithLinkedKey() async {
    final root = await publishRoot(remoteData, atSign);
    final approver = buildMockClient('approver-1');
    await withSigningKey(approver);
    await AtClientSecretSharing.forClient(approver).register();
    final own = (await record(approver, 'approver-1')).keys.single;
    await PqSigningChain(approver).writeLinks('approver-1', {
      own.kid: (
        link: await root.voucher
            .sign(PqSigningChain.linkPayload('approver-1', own)),
        expect: null
      )
    });
    linkCalls.clear();
    return approver;
  }

  group('Given an approver holding the signing root', () {
    test(
        'when it approves B, then it calls enroll:link once for B with a '
        'root link for each key, each expecting none, and B reads anchored',
        () async {
      final (enrollee, enrollment) = await enrolleeWithTwoKeys();
      final approver = buildMockClient('approver-1');
      await AtClientSecretSharing.forClient(approver).register();
      await giveRoot(approver, remoteData);

      final status = await conveyanceFor(approver, privileged: true)
          .conveySecretsTo(enrollment);

      expect(status, KeyPackageStatus.present);
      final keys = (await record(approver, enrolleeId)).keys;
      expect(keys, hasLength(2), reason: 'the premise: K1 and K2 are listed');
      final call = linkCalls.single;
      expect(call.enrollmentId, enrolleeId);
      expect(call.links!.keys, unorderedEquals(keys.map((k) => k.kid)));
      for (final request in call.links!.values) {
        expect(request['expect'], isNull);
        expect(request['link']['payload'], isA<Map>(),
            reason: 'a root link carries its payload as a JSON object');
      }
      final verdict = await PqSigningChain(enrollee.atClient)
          .verifyChain(enrollee, enrolleeId);
      expect(verdict.verdict, ChainVerdict.anchored, reason: verdict.reason);
    });
  });

  group('Given an approver whose own key walks to the root', () {
    for (final privileged in [false, true]) {
      test(
          'when it approves B, then the links are chain links signed with that '
          'key (${privileged ? 'fully privileged' : 'not fully privileged'})',
          () async {
        final (enrollee, enrollment) = await enrolleeWithTwoKeys();
        final approver = await approverWithLinkedKey();

        await conveyanceFor(approver, privileged: privileged)
            .conveySecretsTo(enrollment);

        final links = linkCalls.single.links!.values;
        expect(links, hasLength(2));
        for (final request in links) {
          expect(request['link']['signatures'], hasLength(1),
              reason: 'a chain link is a JWS carrying its signer\'s one '
                  'signature');
        }
        final verdict = await PqSigningChain(enrollee.atClient)
            .verifyChain(enrollee, enrolleeId);
        expect(verdict.verdict, ChainVerdict.anchored, reason: verdict.reason);
      });
    }
  });

  group('Given an approver holding neither the root nor a linked key', () {
    test(
        'when it approves B, then it sends no enroll:link, and the symmetric '
        'key still arrives', () async {
      final (enrollee, enrollment) = await enrolleeWithTwoKeys();
      final approver = buildMockClient('approver-1');
      await withSigningKey(approver);
      await AtClientSecretSharing.forClient(approver).register();

      final conveyance = conveyanceFor(approver, privileged: true);
      await conveyance.conveyMintedApkamSymmetricKey(enrollment, 'MINTED');
      final status = await conveyance.conveySecretsTo(enrollment);

      expect(status, KeyPackageStatus.present);
      expect(linkCalls, isEmpty);
      expect(await enrollee.sweepOnce(), greaterThan(0));
      final names =
          enrollee.secretStore.listSecrets().map((s) => s.name).toList();
      expect(names, contains(enrollmentApkamSymmetricKeySecretName),
          reason: 'the symmetric key is what the enrollee is blocked polling '
              'for; a missing link must never cost it that');
    });
  });

  group('Given an approver that links', () {
    test('when it approves B, then no link travels in an envelope', () async {
      final (enrollee, enrollment) = await enrolleeWithTwoKeys();
      final approver = buildMockClient('approver-1');
      await AtClientSecretSharing.forClient(approver).register();
      await giveRoot(approver, remoteData);

      final conveyance = conveyanceFor(approver, privileged: true);
      await conveyance.conveyMintedApkamSymmetricKey(enrollment, 'MINTED');
      await conveyance.conveySecretsTo(enrollment);

      expect(linkCalls, hasLength(1), reason: 'the premise: it linked');
      expect(await enrollee.sweepOnce(), greaterThan(0));
      expect(
          enrollee.secretStore.listSecrets().map((s) => s.name).where(
              (n) => n.contains('apskChainLink') || n.contains('apskRootLink')),
          isEmpty);
    });

    test(
        'when B advertised no key package, then B\'s keys are linked all '
        'the same', () async {
      final (enrollee, enrollment) =
          await enrolleeWithTwoKeys(keyPackage: false);
      final approver = buildMockClient('approver-1');
      await AtClientSecretSharing.forClient(approver).register();
      await giveRoot(approver, remoteData);

      final status = await conveyanceFor(approver, privileged: true)
          .conveySecretsTo(enrollment);

      expect(status, KeyPackageStatus.absent);
      expect(linkCalls.single.enrollmentId, enrolleeId);
      expect(
          (await PqSigningChain(enrollee.atClient)
                  .verifyChain(enrollee, enrolleeId))
              .verdict,
          ChainVerdict.anchored);
    });

    test(
        'when B\'s _apsk is its authentication key, then it sends no '
        'enroll:link and B reads unsigned', () async {
      final enrolleeClient = buildMockClient(enrolleeId);
      final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
      await enrollee.register();
      final enrollment = Enrollment()
        ..enrollmentId = enrolleeId
        ..namespace = {namespace: 'rw'}
        ..apkamPublicKey =
            pkamKeyPairFor(atSign, enrolleeId).atPublicKey.publicKey;
      final approver = buildMockClient('approver-1');
      await AtClientSecretSharing.forClient(approver).register();
      await giveRoot(approver, remoteData);

      await conveyanceFor(approver, privileged: true)
          .conveySecretsTo(enrollment);

      expect(linkCalls, isEmpty);
      expect(
          (await PqSigningChain(enrolleeClient)
                  .verifyChain(enrollee, enrolleeId))
              .verdict,
          ChainVerdict.unsigned);
    });
  });

  group('Given an atServer without enroll:link', () {
    for (final support in [
      EnrollLinkSupport.unknownToGrammar,
      EnrollLinkSupport.noHandler,
    ]) {
      test(
          'when an approver holding the root approves B and the atServer is '
          '$support, then nothing is linked and the conveyance completes',
          () async {
        final (enrollee, enrollment) = await enrolleeWithTwoKeys();
        final approver = buildMockClient('approver-1', enrollLink: support);
        await AtClientSecretSharing.forClient(approver).register();
        await giveRoot(approver, remoteData);

        final conveyance = conveyanceFor(approver, privileged: true);
        await conveyance.conveyMintedApkamSymmetricKey(enrollment, 'MINTED');
        final status = await conveyance.conveySecretsTo(enrollment);

        expect(status, KeyPackageStatus.present);
        expect(linkCalls, isNotEmpty, reason: 'the premise: it tried');
        expect(
            (await PqSigningChain(enrollee.atClient)
                    .verifyChain(enrollee, enrolleeId))
                .verdict,
            ChainVerdict.unsigned);
        expect(await enrollee.sweepOnce(), greaterThan(0));
        expect(enrollee.secretStore.listSecrets().map((s) => s.name),
            contains(enrollmentApkamSymmetricKeySecretName));
      });
    }
  });
}
