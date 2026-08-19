// The enrollment key-package surface is @experimental; driving it is the point.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyPackage, PackageKey;
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope, verifyEnvelope;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:test/test.dart';

import 'test_utils.dart';

/// KE-2's writer against a live atServer — UC-A2.5 and UC-A2.6
/// (`docs/projects/pq/acceptance.md`).
///
/// **Neither row can be proven against a mock**, which is why they sat blocked
/// on `blockers.dart`'s `ke2` long after the mechanism existed:
///
/// - UC-A2.5 asserts what comes back from `enroll:listns` after the amendment.
///   A fake that echoes what it was handed proves the client composed a
///   request, not that a record was rewritten.
/// - UC-A2.6 is the atServer *refusing*. A mocked lookup that accepts
///   everything makes the self-only interlock's presence and its absence
///   indistinguishable, so the unit suite is green either way.
///
/// Every enrollment uses a run-unique device name: enrollment state is
/// one-shot, so an `(appName, deviceName)` pair that is already approved is
/// refused, and a file that hard-codes one passes on a fresh virtualenv and
/// fails on the second run against the same one.
void main() {
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';
  const rootDomain = 'vip.ve.atsign.zone';

  final runId = DateTime.now().microsecondsSinceEpoch;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    approver = manager.atClient;
  });

  AtLookUp lookupOf(EnrolledClient c) =>
      c.client.getRemoteSecondary()!.atLookUp;

  /// Enrols and authenticates a client whose preference advertises
  /// [algorithms], sharing one keyfile with the test so that what
  /// `KeyPackageMinting` files is what this test can read back.
  Future<EnrolledClient> enrol(String device, List<String> algorithms) async {
    final keysIo = InMemoryAtKeysIo();
    return enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign,
          keyEstablishmentAlgorithms: algorithms),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      deviceName: '$device-$runId',
      atKeysIo: keysIo,
    );
  }

  /// The key package the atServer is serving for [client], **verified the way
  /// a peer verifies it** — against the enrollment's own advertised signing
  /// key. A package that does not verify is one no sender acts on, so reading
  /// the payload without this would assert something the ecosystem ignores.
  ///
  /// ⚠️ **Read through `enroll:listns`, NOT `enroll:fetch`.** This used
  /// `enroll:fetch` and got a null: that verb returns exactly five fields
  /// (appName, deviceName, namespace, encryptedAPKAMSymmetricKey, status) and
  /// `metadata` is not among them — a fact `enroll_update_live_test.dart`
  /// already recorded, and which one probe would have shown. `listns` is the
  /// verb a *peer* discovers a key package through, so reading it here asserts
  /// what a sender would actually see.
  Future<KeyPackage> servedPackage(EnrolledClient client) async {
    final raw = await lookupOf(client)
        .executeCommand('enroll:listns:$namespace\n', auth: true);
    final decoded =
        jsonDecode(raw!.replaceFirst(RegExp(r'^data:'), '')) as List;
    final mine = decoded.cast<Map<String, dynamic>>().firstWhere(
        (e) => e['enrollmentId'] == client.enrollmentId,
        orElse: () => throw StateError(
            'enroll:listns returned no entry for ${client.enrollmentId}; '
            'without it this row asserts nothing'));
    final metadata = mine['metadata'];
    expect(metadata, isA<Map>(),
        reason: 'the enrollment advertises no metadata at all, so there is no '
            'key package to have amended');
    final envelope = SignedEnvelope.fromJson(
        (metadata as Map).cast<String, dynamic>()['keyPackage']
            as Map<String, dynamic>);
    // Verified against the `_apsk` the atServer is SERVING, not against the
    // key this test happens to hold. A peer has only the record, so checking
    // the package against a locally-remembered key would prove something no
    // sender can reproduce — and would still pass if the amendment published
    // an advertisement that disagreed with what it signed.
    final apskKey = 'public:_apsk.${client.enrollmentId}.'
        '${EnrollmentConstants.perEnrollmentApproved}$atSign';
    final apsk = await lookupOf(client)
        .executeCommand('llookup:$apskKey\n', auth: true);
    expect(apsk, startsWith('data:'),
        reason: 'without the advertised signing key there is nothing to '
            'verify the package against, and this row would assert only that '
            'some JSON came back');
    await verifyEnvelope(envelope,
        signerPublicKey: apsk!.replaceFirst('data:', '').trim(),
        expecting: EnvelopeType.keyPackage);
    return KeyPackage.fromPayload(envelope.payload,
        enrollmentId: client.enrollmentId);
  }

  test('UC-A2.5 · an enrollment amends its own key package', () async {
    // A DIFFERENTIAL, because the single-client version races: the PQ startup
    // is fired unawaited by the client's init, so a "before" read taken after
    // enrolAndAuthenticate returns may land either side of the amendment. Both
    // arms below are read only after their startup has completed, so neither
    // depends on timing — and the varied thing is the configured list alone.
    //
    // The control arm also proves the premise the amendment arm needs: that
    // the creating enroll:request carries exactly ONE key. Asserting that from
    // the harness's source instead would be inheriting a claim.
    final single =
        await enrol('a25-single', const [SecretSharingAlgos.xWing]);
    final both = await enrol('a25-amend',
        const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

    await (single.client as AtClientImpl).pqBootstrap!.startupComplete;
    await (both.client as AtClientImpl).pqBootstrap!.startupComplete;

    // Control: a client whose list matches what it was created with leaves the
    // record alone. One key, and it is the X-Wing one the request carried.
    final unchanged = await servedPackage(single);
    expect(unchanged.keys, hasLength(1),
        reason: 'an enrollment is created advertising one key, and a startup '
            'that finds nothing missing must not rewrite the record');
    expect(unchanged.keys.single.alg, SecretSharingAlgos.xWing);

    // THEN the amendment arm's record has gained a key.
    final amended = await servedPackage(both);
    expect(amended.keys.map((k) => k.alg).toSet(),
        {SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024},
        reason: 'a package can now gain a key — the claim KE-2 existed for. '
            'The control arm shows both started from one');

    // The address the enrollment was created with survives, still active:
    // this row is about GAINING a key, and an amendment that moved the
    // enrollment would strand every secret already sealed to the old kpid.
    final original =
        amended.keys.where((k) => k.kid == both.kpid).toList();
    expect(original, hasLength(1),
        reason: 'the key the enrollment advertised at creation keeps its '
            'address — EnrolledClient.kpid is what secrets were sealed to');
    expect(original.single.status, KeyEntryStatus.active);

    // Suites are DERIVED from the package's own keys rather than stated, so
    // gaining a key widens what the package claims it can open — and a claim
    // it cannot back is a defect nobody but this enrollment could repair.
    expect(amended.suites,
        containsAll(SecretSharingAlgos.openableSuitesForAll(
            const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024])),
        reason: 'the suites list covers both KEMs, derived from the keys');

    // And it still verifies against this enrollment's _apsk — servedPackage
    // throws otherwise, so reaching here is the assertion. The update path
    // relaxes no signature check.
  });

  test('UC-A2.6 · only the enrollment itself may amend its metadata',
      () async {
    final mine = await enrol('a26-mine', const [SecretSharingAlgos.xWing]);
    final other = await enrol('a26-other', const [SecretSharingAlgos.xWing]);

    // A well-formed metadata amendment, so that every refusal below is about
    // WHO asked rather than about the request being malformed. Sent from three
    // connections.
    //
    // The public key is real base64 of the right length rather than a
    // placeholder: `PackageKey` derives its kid by base64-DECODING `pub`, so
    // 'not-a-real-key' throws a FormatException in the test's own setup and
    // never reaches the wire — which reddens the row without testing anything.
    // The bytes need not be a usable key: the atServer treats metadata as
    // opaque, and what these arms assert is the identity check in front of it.
    final pub = base64Encode(List<int>.filled(1216, 7));
    Map<String, dynamic> amendment() => {
          'keyPackage': KeyPackage.payloadFor(
            createdAt: DateTime.now().toUtc(),
            keys: [
              PackageKey(
                  use: SecretSharingAlgos.useEnc,
                  alg: SecretSharingAlgos.xWing,
                  pub: pub)
            ],
          )
        };

    // Arm 1: one approved enrollment reaching for another's record.
    await expectLater(
        AtEnrollment.create().update(
            EnrollmentUpdateRequest(
                enrollmentId: other.enrollmentId,
                metadata: amendment()),
            lookupOf(mine)),
        throwsA(isA<Object>()),
        reason: 'holding one enrollment grants nothing over another, and a '
            'key package is an encapsulation target — being able to rewrite '
            "someone else's would let an attacker redirect their secrets");

    // Arm 2: a connection carrying no enrollment id at all — the owner's own,
    // authenticated over legacy PKAM. This is the arm that goes green for the
    // wrong reason if the check is written as an authorization lookup rather
    // than an identity test, because isAuthorized short-circuits a connection
    // with no enrollment id to TRUE.
    await expectLater(
        AtEnrollment.create().update(
            EnrollmentUpdateRequest(
                enrollmentId: mine.enrollmentId,
                metadata: amendment()),
            approver.getRemoteSecondary()!.atLookUp),
        throwsA(isA<Object>()),
        reason: 'an owner connection names no enrollment, so it cannot BE the '
            'enrollment this record belongs to — despite carrying full '
            'permissions everywhere else');

    // The control, in the same session: the same shape of request on its OWN
    // connection is accepted. Without it the two refusals would prove only
    // that the verb refuses everything.
    final ok = await AtEnrollment.create().update(
        EnrollmentUpdateRequest(
            enrollmentId: mine.enrollmentId,
            metadata: amendment()),
        lookupOf(mine));
    expect(ok.enrollmentId, mine.enrollmentId);
  });
}
