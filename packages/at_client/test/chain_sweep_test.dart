// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show
        apskAdvertisement,
        AtEnrollment,
        ApskSigningKey,
        AtKeys,
        CryptographicMaterial,
        CryptographicMaterialRole,
        InMemoryAtKeysIo,
        CryptographicMaterialAlgorithm;
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_client/src/secret_sharing/envelope_addressing.dart'
    show EnvelopeAddressing;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

/// Generation 1 of a root filed under the algorithm this build mints.
final rootSlot1 =
    '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1';

/// The sweep anchors enrollments to the signing root.
///
/// The sweeper only runs when fully privileged (`rw` on `*` and `__manage`),
/// and that class signs **root** links — one hop, verified against the
/// published signing root — never chain links attributed to itself. The
/// population it exists for: a scoped enrollment approved by the legacy
/// parent (which could sign nothing), and any enrollment carrying only a
/// provisional chain link — root-anchored is the terminal state, and the
/// sweep is what makes it every enrollment's state.
void main() {
  const atSign = '@alice';
  const enrolleeId = 'scoped-1';
  const namespace = 'buzz';
  late Map<String, String> remoteData;
  late Map<String, Metadata> remoteMetadata;

  setUpAll(() => registerFallbackValue(AtKey()));
  setUp(() {
    remoteData = {};
    remoteMetadata = {};
  });

  MockAtClient buildMockClient(String enrollmentId) {
    final atClient = buildRemoteBackedMockClient(
        atSign: atSign,
        enrollmentId: enrollmentId,
        remoteData: remoteData,
        remoteMetadata: remoteMetadata);
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

  /// Gives [client] the atSign's signing root — the private in its keys and
  /// the record published — the state a fully privileged enrollment is
  /// entitled to reach. Built directly rather than through `mintIfAbsent`,
  /// whose publish rides `executeVerb`, which this fixture does not model.
  Future<void> giveRoot(MockAtClient client) async {
    final pair = await MlDsa65PureDartAlgo().generateKeyPair();
    final io = InMemoryAtKeysIo();
    await io.write(
        atSign,
        AtKeys()
          ..addKey(CryptographicMaterial(
            keyId: rootSlot1,
            role: CryptographicMaterialRole.privateSigning,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            bytes: AtBytes(pair.secretKey),
            createdAt: DateTime.now().toUtc(),
          )));
    when(() => client.atKeysIo).thenReturn(io);
    remoteData['public:${PqSigningRoot.recordName}$atSign'] =
        jsonEncode(apskAdvertisement(keys: [
      ApskSigningKey.forPublicKey(
          alg: PqSigningRoot.rootKeyAlgo, pub: base64Encode(pair.publicKey))
    ]));
  }

  /// Stubs the approved-filter `enroll:list` this sweep issues.
  void stubApprovedList(AtClient sweeperClient, Object keyPackage) {
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list
          ..enrollmentStatusFilter = [EnrollmentStatus.approved])
        .buildCommand();
    final key = '$enrolleeId.new.enrollments.__manage$atSign';
    final secondary = sweeperClient.getRemoteSecondary()!;
    when(() => secondary.executeCommand(listCommand, auth: true))
        .thenAnswer((_) async => 'data:${jsonEncode({
                  key: {
                    'appName': 'buzz',
                    'deviceName': 'pixel',
                    'namespace': {namespace: 'rw'},
                    'metadata': {'keyPackage': keyPackage},
                  }
                })}');
  }

  test(
      'the sweep anchors an unanchored enrollment to the root, and stops '
      'once it has stamped', () async {
    // The scoped enrollment: registered (its _apsk is published), approved,
    // no links — the state a legacy-parent approval leaves it in.
    final enrolleeClient = buildMockClient(enrolleeId);
    final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
    await enrollee.register();
    final advertised = await enrollee.signedKeyPackagePayload();

    // The sweeper: a distinct, registered enrollment holding the root
    // private. Privilege is the caller's gate (the bootstrap checks it); the
    // sweep itself is exercised directly here.
    final sweeperClient = buildMockClient('sweeper-1');
    await AtClientSecretSharing.forClient(sweeperClient).register();
    await giveRoot(sweeperClient);
    stubApprovedList(sweeperClient, advertised);

    final service = EnrollmentServiceImpl(sweeperClient, AtEnrollment.create());
    expect(await service.sweepUnanchoredEnrollments(), 1,
        reason: 'one approved enrollment lacks a root link, so exactly one '
            'is signed and conveyed');

    // The enrollee receives the link and stamps its own _apsk — the sweep
    // cannot stamp it directly, because _apsk accepts writes only from its
    // own enrollment's connection.
    expect(await enrollee.sweepOnce(), greaterThan(0));
    await PqSigningChain(enrolleeClient).publishPendingLink();

    expect(
        await PqSigningChain(sweeperClient).readRootLink(enrolleeId), isNotNull,
        reason: 'the sweeper is fully privileged, and that class signs ROOT '
            'links — one hop, nothing provisional — never chain links '
            'attributed to itself');
    expect(await PqSigningChain(sweeperClient).readLink(enrolleeId), isNull,
        reason: 'the differential against the old design: no chain link was '
            'conveyed or stamped anywhere in this flow');

    final result =
        await PqSigningChain(enrolleeClient).verifyChain(enrollee, enrolleeId);
    expect(result.verdict, ChainVerdict.anchored,
        reason: 'the stamped link must verify against the published signing '
            'root — a root link that only LOOKS like one vouches for '
            'nothing. Reason if not: ${result.reason}');

    expect(await service.sweepUnanchoredEnrollments(), 0,
        reason: 'root-anchored is the terminal state — the sweep is '
            'convergent, not a broadcast that repeats forever');
  });

  test('the sweep upgrades a chain-linked enrollment to a root link', () async {
    final enrolleeClient = buildMockClient(enrolleeId);
    final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
    await enrollee.register();
    final advertised = await enrollee.signedKeyPackagePayload();

    // A provisional chain link from a parent enrollment, already stamped on
    // the record — the state an approve by a non-fully-privileged approver
    // leaves behind.
    final parentClient = buildMockClient('parent-1');
    final parent = AtClientSecretSharing.forClient(parentClient);
    await parent.register();
    final chainLink =
        await PqSigningChain(parentClient).signLinkFor(parent, enrolleeId);
    await PqSigningChain(enrolleeClient).publishLink(enrolleeId, chainLink!);
    expect(await PqSigningChain(enrolleeClient).readLink(enrolleeId), isNotNull,
        reason: 'the precondition that makes this an upgrade test at all');

    final sweeperClient = buildMockClient('sweeper-1');
    await AtClientSecretSharing.forClient(sweeperClient).register();
    await giveRoot(sweeperClient);
    stubApprovedList(sweeperClient, advertised);

    final service = EnrollmentServiceImpl(sweeperClient, AtEnrollment.create());
    expect(await service.sweepUnanchoredEnrollments(), 1,
        reason: 'a chain link is provisional, not terminal: an enrollment '
            'carrying only one is exactly what the sweep upgrades');

    expect(await enrollee.sweepOnce(), greaterThan(0));
    await PqSigningChain(enrolleeClient).publishPendingLink();

    final result =
        await PqSigningChain(enrolleeClient).verifyChain(enrollee, enrolleeId);
    expect(result.verdict, ChainVerdict.anchored,
        reason: 'after the upgrade the walk ends at the root in one hop, '
            'whatever the provisional link said. Reason if not: '
            '${result.reason}');
  });

  test('a privileged sweeper without the root private conveys nothing',
      () async {
    final enrolleeClient = buildMockClient(enrolleeId);
    final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
    await enrollee.register();
    final advertised = await enrollee.signedKeyPackagePayload();

    final sweeperClient = buildMockClient('sweeper-1');
    await AtClientSecretSharing.forClient(sweeperClient).register();
    // Deliberately no giveRoot: entitled but not yet holding.
    stubApprovedList(sweeperClient, advertised);

    final envelopesBefore =
        remoteData.keys.where((k) => k.contains('.__ssenv.')).length;
    expect(
        await EnrollmentServiceImpl(sweeperClient, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        0,
        reason: 'this sweep signs root links or nothing, and it holds no '
            'root private. It is not the approval path, which in this same '
            'state conveys a chain link rather than leave an enrolment '
            'unsigned: an approval happens once, while this sweep runs again '
            'at every start of every privileged client');
    expect(remoteData.keys.where((k) => k.contains('.__ssenv.')).length,
        envelopesBefore,
        reason: 'nothing was conveyed under any name — a chain link sent '
            'here would be the old design surviving under a new count');
  });

  test('a conveyed root link that does not verify is refused, not stamped',
      () async {
    final enrolleeClient = buildMockClient(enrolleeId);
    final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
    final enrolleePackage = await enrollee.register();

    // A genuine published root, so the refusal below is attributable to the
    // bad signature rather than to there being nothing to verify against.
    final minterClient = buildMockClient('minter-1');
    await AtClientSecretSharing.forClient(minterClient).register();
    await giveRoot(minterClient);

    final published = await enrolleeClient.get(
        AtKey.fromString(PqSigningChain.apskUri(atSign, enrolleeId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    final forged = {
      'v': 1,
      'alg': PqSigningChain.rootLinkAlgo,
      'payload': PqSigningChain.linkPayload(
        childEnrollmentId: enrolleeId,
        childApkamPublicKey: published.value as String,
      ),
      'signature': base64Encode(List<int>.filled(64, 7)),
    };
    await AtClientSecretSharing.forClient(minterClient).shareSecretWith(
        enrolleePackage,
        Secret(
          namespace: namespace,
          name: PqSigningChain.rootLinkSecretName,
          value: PqSigningChain.encodeLink(forged),
        ),
        inReplyTo: EnvelopeAddressing.unsolicited);

    expect(await enrollee.sweepOnce(), greaterThan(0));
    expect(await PqSigningChain(enrolleeClient).publishPendingLink(), isFalse,
        reason: 'the conveyance channel authenticates the SENDER, and the '
            'sender is not the root — a link is stamped only after verifying '
            'against the published signing root');
    expect(
        await PqSigningChain(enrolleeClient).readRootLink(enrolleeId), isNull,
        reason: 'a forged anchor on the published identity record would be '
            'worse than no anchor');
  });

  test('an enrollment with no key package is skipped, not failed', () async {
    final sweeperClient = buildMockClient('sweeper-2');
    await AtClientSecretSharing.forClient(sweeperClient).register();
    // The sweeper holds the root, so the skip below is attributable to the
    // missing package rather than to having nothing to sign with.
    await giveRoot(sweeperClient);
    final listCommand = (EnrollVerbBuilder()
          ..operation = EnrollOperationEnum.list
          ..enrollmentStatusFilter = [EnrollmentStatus.approved])
        .buildCommand();
    final secondary = sweeperClient.getRemoteSecondary()!;
    when(() => secondary.executeCommand(listCommand, auth: true))
        .thenAnswer((_) async => 'data:${jsonEncode({
                  'legacy-1.new.enrollments.__manage$atSign': {
                    'appName': 'old',
                    'deviceName': 'laptop',
                    'namespace': {namespace: 'rw'},
                  }
                })}');

    expect(
        await EnrollmentServiceImpl(sweeperClient, AtEnrollment.create())
            .sweepUnanchoredEnrollments(),
        0,
        reason: 'a legacy enrollment has no conveyance channel and no PQ key '
            'to vouch for — skipping it is the design, not a failure');
  });
}
