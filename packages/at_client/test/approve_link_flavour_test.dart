// The substrate is deliberately marked @experimental and will be reshaped as
// the group surface matures.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show
        apskAdvertisement,
        ApskSigningKey,
        AtKeys,
        CryptographicMaterial,
        CryptographicMaterialRole,
        InMemoryAtKeysIo,
        CryptographicMaterialAlgorithm;
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo, RsaKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/enroll/privilege_resolver.dart'
    show EnrollmentPrivilegeResolver;
import 'package:at_client/src/service/envelope_enrollment_conveyance.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

class _FakePrivilege implements EnrollmentPrivilegeResolver {
  _FakePrivilege(this.answer);
  final bool answer;

  @override
  Future<bool> isFullyPrivileged() async => answer;

  @override
  Future<bool> isEnrollmentFullyPrivileged(String enrollmentId) async => answer;
}

/// Generation 1 of a root filed under the algorithm this build mints.
final rootSlot1 =
    '${PqSigningRoot.keyIdPrefixFor(PqSigningRoot.rootKeyAlgoToken)}1';

/// Which link flavour an approval conveys is decided by the APPROVER's
/// privilege: the fully privileged class (`rw` on `*` and `__manage`) signs
/// root links — one hop, verified against the published signing root — and
/// only a non-privileged approver leaves the provisional chain link.
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
  /// the record published. Built directly rather than through `mintIfAbsent`,
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

  /// Gives [client] a data signing key of its own and **no** signing root —
  /// the middle arm: entitled, unpossessed, but able to sign something.
  ///
  /// A real keypair, because the link is actually signed with it.
  Future<void> giveSigningKey(MockAtClient client, String enrollmentId) async {
    final pair = RsaKeyPair.generate();
    final io = InMemoryAtKeysIo();
    final keys = AtKeys()
      ..fileSigningMaterial(
        enrollmentId: enrollmentId,
        algorithm: CryptographicMaterialAlgorithm.rsa2048,
        publicKey: pair.atPublicKey.publicKey,
        privateKey: pair.atPrivateKey.privateKey,
      );
    await io.write(atSign, keys);
    when(() => client.atKeysIo).thenReturn(io);
  }

  /// A registered enrollee plus the [Enrollment] record its approval reads.
  Future<(AtClientSecretSharing, Enrollment)> registeredEnrollee() async {
    final enrolleeClient = buildMockClient(enrolleeId);
    final enrollee = AtClientSecretSharing.forClient(enrolleeClient);
    await enrollee.register();
    final advertised = await enrollee.signedKeyPackagePayload();
    final enrollment = Enrollment()
      ..enrollmentId = enrolleeId
      ..namespace = {namespace: 'rw'}
      ..metadata = {'keyPackage': advertised.toJson()};
    return (enrollee, enrollment);
  }

  EnvelopeEnrollmentConveyance conveyanceFor(MockAtClient approver,
          {required bool privileged}) =>
      EnvelopeEnrollmentConveyance(approver,
          listEnrollments: ({enrollmentListParams}) async => [],
          privilege: _FakePrivilege(privileged));

  test('a fully privileged approver conveys a root link', () async {
    final (enrollee, enrollment) = await registeredEnrollee();
    final approver = buildMockClient('approver-1');
    await AtClientSecretSharing.forClient(approver).register();
    await giveRoot(approver);

    final status = await conveyanceFor(approver, privileged: true)
        .conveySecretsTo(enrollment);
    expect(status, KeyPackageStatus.present);

    expect(await enrollee.sweepOnce(), greaterThan(0));
    final names = enrollee.secretStore.listSecrets().map((s) => s.name);
    expect(names, contains(PqSigningChain.rootLinkSecretName),
        reason: 'the fully privileged class anchors the enrollments it '
            'vouches for directly to the root — born anchored, not healed '
            'later by the sweep');
    expect(names, isNot(contains(PqSigningChain.linkSecretName)),
        reason: 'the differential against the old design: root INSTEAD OF '
            'chain, not alongside it');

    final enrolleeClient = enrollee.atClient;
    await PqSigningChain(enrolleeClient).publishPendingLink();
    final result =
        await PqSigningChain(enrolleeClient).verifyChain(enrollee, enrolleeId);
    expect(result.verdict, ChainVerdict.anchored,
        reason: 'the conveyed link must verify against the published signing '
            'root, not merely look like one. Reason if not: ${result.reason}');
  });

  test('a non-privileged approver conveys the provisional chain link',
      () async {
    final (enrollee, enrollment) = await registeredEnrollee();
    final approver = buildMockClient('approver-1');
    await AtClientSecretSharing.forClient(approver).register();

    final status = await conveyanceFor(approver, privileged: false)
        .conveySecretsTo(enrollment);
    expect(status, KeyPackageStatus.present);

    expect(await enrollee.sweepOnce(), greaterThan(0));
    final names = enrollee.secretStore.listSecrets().map((s) => s.name);
    expect(names, contains(PqSigningChain.linkSecretName),
        reason: 'approval takes __manage, not necessarily *: an approver '
            'outside the fully privileged class still vouches, provisionally, '
            'and the sweep upgrades it later');
    expect(names, isNot(contains(PqSigningChain.rootLinkSecretName)),
        reason: 'it holds no root and signs no root links');
  });

  test(
      'a privileged approver holding NEITHER conveys no link, '
      'and everything else still flows', () async {
    final (enrollee, enrollment) = await registeredEnrollee();
    final approver = buildMockClient('approver-1');
    await AtClientSecretSharing.forClient(approver).register();
    // Deliberately neither giveRoot nor giveSigningKey.

    final status = await conveyanceFor(approver, privileged: true)
        .conveySecretsTo(enrollment, mintedApkamSymmetricKey: 'MINTED');
    expect(status, KeyPackageStatus.present);

    expect(await enrollee.sweepOnce(), greaterThan(0));
    final names =
        enrollee.secretStore.listSecrets().map((s) => s.name).toList();
    expect(names, contains(enrollmentApkamSymmetricKeySecretName),
        reason: 'the symmetric key is what the enrollee is blocked polling '
            'for; a missing link must never cost it that');
    expect(names, isNot(contains(PqSigningChain.linkSecretName)),
        reason: 'this approver holds no data signing key either, so the only '
            'thing left to sign with is the APKAM authentication key — and '
            'that key is DROPPED from the advertisement rather than retired, '
            'so the link would become permanently unverifiable. Silence is '
            'the honest outcome');
    expect(names, isNot(contains(PqSigningChain.rootLinkSecretName)),
        reason: 'nothing to sign a root link with either; the sweep anchors '
            'this enrollment once possession heals');
  });

  test(
      'a privileged approver with a data signing key but no root conveys a '
      'CHAIN link', () async {
    // ⛔ The arm that changed. It conveyed nothing until 2026-08-30, on the
    // grounds that possession heals by pulling and the sweep would anchor the
    // enrollment then. Measured: `requestPrivateIfAbsent` has exactly one
    // production caller, a startup step, and the sweep that would anchor a
    // missed enrollment is a later startup step — so nothing re-attempts the
    // link for an enrollment approved while its approver was unpossessed. It
    // stays unsigned until some privileged root-holder next STARTS UP, which
    // is unbounded for a long-running approver. Provisional beats absent.
    final (enrollee, enrollment) = await registeredEnrollee();
    final approver = buildMockClient('approver-1');
    // Before register(), because giving the key replaces this client's
    // AtKeysIo and a registration written to the old one would be discarded —
    // and conveying a minted symmetric key needs the approver registered.
    await giveSigningKey(approver, 'approver-1');
    await AtClientSecretSharing.forClient(approver).register();

    final status = await conveyanceFor(approver, privileged: true)
        .conveySecretsTo(enrollment, mintedApkamSymmetricKey: 'MINTED');
    expect(status, KeyPackageStatus.present);

    expect(await enrollee.sweepOnce(), greaterThan(0));
    final names =
        enrollee.secretStore.listSecrets().map((s) => s.name).toList();
    expect(names, contains(PqSigningChain.linkSecretName),
        reason: 'it can sign something that keeps verifying, so it vouches '
            'provisionally rather than leaving the enrollment unsigned');
    expect(names, isNot(contains(PqSigningChain.rootLinkSecretName)),
        reason: 'and it is a CHAIN link, not a root one — the two stamp into '
            'distinct _apsk fields, so a chain link cannot mask the root link '
            'the sweep later adds');
  });
}
