import 'package:at_auth/at_auth.dart' show AtEnrollment;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_commons/at_builders.dart' show EnrollVerbBuilder;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/enroll_link_fake.dart';
import 'test_utils/link_fixtures.dart';
import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';
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

  final logs = RecordedLogs();

  setUpAll(() {
    registerFallbackValue(AtKey());
    logs.installOn();
  });
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
    linkCalls = [];
  });

  MockAtClient client(String enrollmentId,
          {EnrollLinkSupport enrollLink = EnrollLinkSupport.supported}) =>
      buildRemoteBackedMockClient(
          atSign: atSign,
          enrollmentId: enrollmentId,
          remoteData: remoteData,
          remoteMetadata: remoteMetadata,
          enrollLink: enrollLink,
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

  group('Given a root holder and an atServer without enroll:link', () {
    for (final support in [
      EnrollLinkSupport.unknownToGrammar,
      EnrollLinkSupport.noHandler,
    ]) {
      test(
          'UC-G3.27 · when the sweep runs over three enrollments and the '
          'atServer is $support, then it sends one enroll:link and logs the '
          'refusal once', () async {
        const ids = ['e-1', 'e-2', 'e-3'];
        for (final id in ids) {
          await withSigningKey(client(id));
        }
        final sweeper = client('sweeper-1', enrollLink: support);
        await giveRoot(sweeper, remoteData);
        stubApprovedList(
            sweeper, atSign, {for (final id in ids) id: recordOf(id)});
        logs.records.clear();

        expect(
            await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
                .sweepUnanchoredEnrollments(),
            0);

        expect(linkCalls, hasLength(1),
            reason: 'one refusal of the operation itself ends the sweep');
        expect(
            logs
                .at('WARNING')
                .where((m) => m.contains('does not know enroll:link')),
            hasLength(1));
        expect(
            logs.at('WARNING').where((m) =>
                m.contains('Stopped the root-link sweep') &&
                m.contains('e-2') &&
                m.contains('e-3')),
            hasLength(1),
            reason: 'the enrollments left unswept are named');
        expect(logs.at('WARNING').where((m) => m.contains('was refused')),
            isEmpty,
            reason: 'a refusal of the operation itself reads the record no '
                'second time');
      });

      test(
          'UC-G3.27 · when a start links its own keys, sweeps, and links a '
          'key it mints, on an atServer that is $support, then it sends one '
          'enroll:link and logs the refusal once', () async {
        const ids = ['e-1', 'e-2', 'e-3'];
        for (final id in ids) {
          await withSigningKey(client(id));
        }
        final sweeper = client('sweeper-1', enrollLink: support);
        await giveRoot(sweeper, remoteData);
        await withSigningKey(sweeper);
        stubApprovedList(
            sweeper, atSign, {for (final id in ids) id: recordOf(id)});
        final signer = AtClientSecretSharing.forClient(sweeper);
        logs.records.clear();

        await PqSigningChain(sweeper)
            .linkOwnKeys(signer, isFullyPrivileged: () async => true);
        await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
            .sweepUnanchoredEnrollments();
        await PqSigningChain(sweeper)
            .linkOwnKeys(signer, isFullyPrivileged: null);

        expect(linkCalls, hasLength(1),
            reason: 'every step of one client shares what the first refusal '
                'showed');
        expect(
            logs
                .at('WARNING')
                .where((m) => m.contains('does not know enroll:link')),
            hasLength(1));
      });
    }

    test(
        'when the atServer refuses one enrollment\'s links as unauthorised, '
        'then the sweep goes on to the next', () async {
      const ids = ['e-1', 'e-2', 'e-3'];
      for (final id in ids) {
        await withSigningKey(client(id));
      }
      final sweeper = client('sweeper-1');
      await giveRoot(sweeper, remoteData);
      stubApprovedList(
          sweeper, atSign, {for (final id in ids) id: recordOf(id)});
      final remote = sweeper.getRemoteSecondary()!;
      when(() => remote.executeVerb(any(
              that: isA<EnrollVerbBuilder>()
                  .having((b) => b.enrollmentId, 'enrollmentId', 'e-1'))))
          .thenAnswer((inv) async {
        linkCalls.add(inv.positionalArguments.single as EnrollVerbBuilder);
        throw UnAuthorizedException('not authorised to link e-1');
      });

      expect(
          await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
              .sweepUnanchoredEnrollments(),
          2);
      expect(linkCalls.map((c) => c.enrollmentId), ids);
      expect(await verdict(sweeper, 'e-2'), ChainVerdict.anchored);
      expect(await verdict(sweeper, 'e-3'), ChainVerdict.anchored);
    });
  });

  test(
      'Given a root holder whose approved list names primary, when the sweep '
      'runs, then it links nothing for primary, the atSign\'s own '
      'credential, which is treated as the atSign itself, never as an '
      'enrollment', () async {
    final primary = client('primary');
    await withSigningKey(primary);
    final sweeper = client('sweeper-1');
    await giveRoot(sweeper, remoteData);
    stubApprovedList(sweeper, atSign, {'primary': recordOf('primary')});

    expect(
        await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        0);
    expect(linkCalls, isEmpty);
  });

  test(
      'Given a root holder and three enrollments, when a link stored on the '
      'first holds a line separator, then the sweep still links all three',
      () async {
    final separator = String.fromCharCode(0x2028);
    const ids = ['e-1', 'e-2', 'e-3'];
    for (final id in ids) {
      await withSigningKey(client(id));
    }
    final sweeper = client('sweeper-1');
    await giveRoot(sweeper, remoteData);
    stubApprovedList(sweeper, atSign, {for (final id in ids) id: recordOf(id)});
    final firstKid = (await record(sweeper, 'e-1')).keys.single.kid;
    final uri = PqSigningChain.apskUri(atSign, 'e-1');
    remoteMetadata[uri] = (remoteMetadata[uri] ?? Metadata())
      ..appMetadata = AppMetadata(providerId: 'legacy', additional: {
        PqSigningChain.linksField: {
          firstKid: {'note': 'a${separator}b'}
        }
      });

    expect(
        await EnrollmentServiceImpl(sweeper, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        3);
    expect(linkCalls.map((c) => c.enrollmentId), ids,
        reason: 'the stored link travels back as `expect`, and the command '
            'carrying it still reads as enroll:link');
    for (final id in ids) {
      expect(await verdict(sweeper, id), ChainVerdict.anchored, reason: id);
    }
  });
}
