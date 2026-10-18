// The substrate this exercises is marked @experimental.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart' show AtEnrollment;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart' show EnrollVerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/link_fixtures.dart';
import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';
import 'test_utils/test_keypairs.dart';

/// A root holder's sweep gives every key on the atSign's other approved
/// enrollments that lacks a sound root link one, through `enroll:link`.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-G3.23.
void main() {
  const atSign = '@alice';
  const enrolleeId = 'scoped-1';
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMetadata;
  late List<EnrollVerbBuilder> linkCalls;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
    linkCalls = [];
  });

  MockAtClient client(String enrollmentId) => buildRemoteBackedMockClient(
      atSign: atSign,
      enrollmentId: enrollmentId,
      remoteData: remoteData,
      remoteMetadata: remoteMetadata,
      enrollLinkLog: linkCalls);

  Map<String, Object?> recordOf(String enrollmentId) => {
        'appName': 'buzz',
        'deviceName': 'pixel',
        'namespace': {'buzz': 'rw'},
        'apkamPublicKey':
            pkamKeyPairFor(atSign, enrollmentId).atPublicKey.publicKey,
      };

  Future<ApskRecord> record(AtClient c, String id) async =>
      (await PqSigningChain(c).readRecord(id))!;

  Future<ChainVerdict> verdict(AtClient c, String id) async =>
      (await PqSigningChain(c)
              .verifyChain(AtClientSecretSharing.forClient(c), id))
          .verdict;

  /// A root-holding sweeper, the enrollee it lists, and the service.
  Future<
      ({
        MockAtClient sweeper,
        MockAtClient enrollee,
        PublishedRoot root,
        EnrollmentServiceImpl service
      })> sweepSetUp() async {
    final enrollee = client(enrolleeId);
    await withSigningKey(enrollee);
    final sweeper = client('sweeper-1');
    final root = await giveRoot(sweeper, remoteData);
    stubApprovedList(sweeper, atSign, {enrolleeId: recordOf(enrolleeId)});
    return (
      sweeper: sweeper,
      enrollee: enrollee,
      root: root,
      service: EnrollmentServiceImpl(sweeper, AtEnrollment.create()),
    );
  }

  group('Given a root holder and an enrollment whose key has no link', () {
    test(
        'when the sweep runs, then the key gets a root link stating it '
        'found none, and the next sweep links nothing', () async {
      final f = await sweepSetUp();
      final key = (await record(f.sweeper, enrolleeId)).keys.single;

      expect(await f.service.sweepUnanchoredEnrollments(), 1);

      expect(linkCalls.single.enrollmentId, enrolleeId);
      expect(linkCalls.single.links![key.kid]['expect'], isNull);
      expect(await verdict(f.enrollee, enrolleeId), ChainVerdict.anchored);

      expect(await f.service.sweepUnanchoredEnrollments(), 0,
          reason: 'a key whose root link passes its check is left as it is');
      expect(linkCalls, hasLength(1));
    });
  });

  group('Given a key with a chain link', () {
    test(
        'when the sweep runs, then a root link replaces it, the call naming '
        'the chain link it found', () async {
      final f = await sweepSetUp();
      final parent = client('parent-1');
      final parentKey = await withSigningKey(parent);
      final parentEntry = (await record(parent, 'parent-1')).keys.single;
      await PqSigningChain(parent).writeLinks('parent-1', {
        parentEntry.kid: (
          link: await f.root.voucher
              .sign(PqSigningChain.linkPayload('parent-1', parentEntry)),
          expect: null
        )
      });
      final key = (await record(f.sweeper, enrolleeId)).keys.single;
      final chainLink = PqSigningChain.signChainLink(
          PqSigningChain.linkPayload(enrolleeId, key),
          key: parentKey,
          signerEnrollmentId: 'parent-1');
      await PqSigningChain(parent).writeLinks(enrolleeId, {
        key.kid: (link: chainLink, expect: null),
      });
      linkCalls.clear();

      expect(await f.service.sweepUnanchoredEnrollments(), 1);

      expect(linkCalls.single.links![key.kid]['expect'], chainLink);
      final walk = await PqSigningChain(f.enrollee).walkFrom(
          AtClientSecretSharing.forClient(f.enrollee),
          await record(f.enrollee, enrolleeId),
          key);
      expect(walk.path, [enrolleeId],
          reason: 'one hop now: the root link, not the chain through parent');
      expect(walk.verdict, ChainVerdict.anchored);
    });
  });

  group('Given a key whose root link fails its check', () {
    test('when the sweep runs, then it is replaced', () async {
      final f = await sweepSetUp();
      final key = (await record(f.sweeper, enrolleeId)).keys.single;
      final stale = {
        ...await f.root.voucher
            .sign(PqSigningChain.linkPayload(enrolleeId, key)),
        'signature': 'AAAA',
      };
      await PqSigningChain(f.sweeper).writeLinks(enrolleeId, {
        key.kid: (link: stale, expect: null),
      });
      expect(await verdict(f.enrollee, enrolleeId), ChainVerdict.broken,
          reason: 'the premise');
      linkCalls.clear();

      expect(await f.service.sweepUnanchoredEnrollments(), 1);

      expect(linkCalls.single.links![key.kid]['expect'], stale);
      expect(await verdict(f.enrollee, enrolleeId), ChainVerdict.anchored);
    });
  });

  test('a fully privileged sweeper without the root private links nothing',
      () async {
    final enrollee = client(enrolleeId);
    await withSigningKey(enrollee);
    final sweeper = client('sweeper-1');
    stubApprovedList(sweeper, atSign, {enrolleeId: recordOf(enrolleeId)});

    expect(
        await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        0);
    expect(linkCalls, isEmpty,
        reason: 'this sweep writes root links or nothing; the approval path, '
            'which in this state may chain-link, happens once, while this runs '
            'at every privileged start');
  });

  test(
      'a fully privileged sweeper whose own key walks to the root, holding no '
      'root private, links nothing', () async {
    final enrollee = client(enrolleeId);
    await withSigningKey(enrollee);
    final sweeper = client('sweeper-1');
    await withSigningKey(sweeper);
    final root = await publishRoot(remoteData, atSign);
    final own = (await record(sweeper, 'sweeper-1')).keys.single;
    await PqSigningChain(sweeper).writeLinks('sweeper-1', {
      own.kid: (
        link: await root.voucher
            .sign(PqSigningChain.linkPayload('sweeper-1', own)),
        expect: null
      ),
    });
    stubApprovedList(sweeper, atSign, {enrolleeId: recordOf(enrolleeId)});
    expect(
        (await PqSigningChain(sweeper).voucher(
                AtClientSecretSharing.forClient(sweeper),
                isFullyPrivileged: () async => true))
            ?.isRoot,
        isFalse,
        reason: 'the premise: it could chain-link');
    linkCalls.clear();

    expect(
        await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        0);
    expect(linkCalls, isEmpty);
  });

  test(
      'an enrollment whose _apsk is its authentication key is left alone, '
      'and one with no key package is linked all the same', () async {
    final legacy = client('legacy-1');
    await AtClientSecretSharing.forClient(legacy).publishPublicSigningKey();
    final noPackage = client('nopackage-1');
    await withSigningKey(noPackage);
    final sweeper = client('sweeper-1');
    await giveRoot(sweeper, remoteData);
    stubApprovedList(sweeper, atSign, {
      'legacy-1': recordOf('legacy-1'),
      'nopackage-1': recordOf('nopackage-1')
    });

    expect(
        await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        1);
    expect(linkCalls.map((c) => c.enrollmentId), ['nopackage-1'],
        reason: 'a link needs no key package, and an authentication key takes '
            'none, so nothing is sent for the legacy enrollment');
  });
}
