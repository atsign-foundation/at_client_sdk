// The enrollment fixture is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/secret_sharing/key_package_minting.dart'
    show KeyPackageMinting;
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart' show EnrollmentConstants;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The atServer's half of advertised-key verification: it publishes `_apsk`
/// at approval, and refuses one enrollment a write to another's.
void main() {
  TestUtils.isolateStorage('apsk_server_side_test');
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';
  const rootDomain = 'vip.ve.atsign.zone';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  final runId = DateTime.now().microsecondsSinceEpoch;

  Future<EnrolledClient> enrol(String device) => enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
        rootDomain: rootDomain,
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        storage: TestUtils.storage,
      );

  String apskKeyFor(String enrollmentId) =>
      'public:_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
      '$atSign';

  /// Revokes [enrollmentId] once the test is done, so a record the test left
  /// in a deliberately broken state stops being read by every later test that
  /// lists this namespace.
  void revokeAfterwards(String enrollmentId) => addTearDown(() async {
        final revoked = await approver.enrollmentService!.revoke(
            EnrollmentRequestDecision.revoked(enrollmentId, atSign));
        expect(revoked.enrollmentStatus, EnrollmentStatus.revoked);
      });

  /// How a peer listing [namespace] sees [enrolled]'s key package.
  ///
  /// NOTE: a new directory per read. Its signer caches each `_apsk` for five
  /// minutes, so a reused one answers from the record fetched before a heal.
  Future<KeyPackageStatus> packageAsPeersSeeIt(EnrolledClient enrolled) async {
    final members = await VerbEnrollmentDirectory(enrolled.client)
        .listForNamespace(namespace);
    return members
        .singleWhere((m) => m.enrollmentId == enrolled.enrollmentId)
        .keyPackageStatus;
  }

  /// Asserts that a heal left [enrolled]'s published key package refused by
  /// peers, and that the reconcile a start runs next signs it again.
  Future<void> expectTheHealedPackageIsSignedAgain(
      EnrolledClient enrolled) async {
    expect(await packageAsPeersSeeIt(enrolled), KeyPackageStatus.rejected,
        reason: 'precondition: the package was signed by the authentication '
            'key, which the heal has just removed from `_apsk`');

    final reconciled =
        await KeyPackageMinting(enrolled.client).reconcileKeyPackage();
    expect(reconciled.minted, isEmpty,
        reason: 'no key changes; only the signature does');

    expect(await packageAsPeersSeeIt(enrolled), KeyPackageStatus.present,
        reason: 'a package no peer accepts leaves the enrollment unreachable '
            'for anything sealed to it, so the reconcile signs it again under '
            'the key `_apsk` now names');
  }

  test(
      'the atServer publishes _apsk itself, and refuses a cross-enrollment '
      'overwrite', () async {
    final victim = await enrol('apsk-victim');
    final attacker = await enrol('apsk-attacker');
    // The attacker ends this test with a junk `_apsk` it wrote itself.
    revokeAfterwards(attacker.enrollmentId);

    expect(attacker.enrollmentId, isNot(victim.enrollmentId),
        reason: 'the attack under test is one enrollment reaching for '
            'another\'s record; with one enrollment there is nothing to reach '
            'for and the refusal below would be meaningless');

    // NOTE: nothing in this test wrote this record — the atServer did, at
    // approval.
    final published = await approver.getRemoteSecondary()!.executeCommand(
        'llookup:${apskKeyFor(victim.enrollmentId)}\n',
        auth: true);
    expect(published, isNotNull);
    expect(published, contains('data:'),
        reason: 'a verifier meeting a freshly approved enrollment must find '
            'its signing key already there. Without it the verifier can only '
            'reject a legitimate peer or trust one unverified');
    final original = published!.replaceFirst('data:', '').trim();
    expect(original, isNotEmpty);

    final attackerLookup = TestUtils.lookUpAs(atSign, attacker.keys,
        enrollmentId: attacker.enrollmentId);

    try {
      expect(
          await attackerLookup.pkamAuthenticate(
              enrollmentId: attacker.enrollmentId),
          true,
          reason: 'the attacker enrollment is approved and must authenticate, '
              'or nothing below tests write restriction');

      final overwrite = (UpdateVerbBuilder()
            ..atKey = (AtKey()
              ..key = '_apsk.${victim.enrollmentId}.'
                  '${EnrollmentConstants.perEnrollmentApproved}'
              ..sharedBy = atSign
              ..metadata = (Metadata()..isPublic = true))
            ..value = 'attacker-substituted-signing-key')
          .buildCommand();

      // NOTE: matched on the reason, naming both the asking enrollment and the
      // key it reached for — a bare throwsA is satisfied by a malformed verb,
      // leaving the test green for the absence of an effect.
      await expectLater(
          attackerLookup.executeCommand(overwrite),
          throwsA(predicate((e) =>
              e is AtLookUpException &&
              '$e'.contains('not authorized to update key') &&
              '$e'.contains(attacker.enrollmentId) &&
              '$e'.contains(victim.enrollmentId))),
          reason: 'an enrollment must not be able to write another\'s _apsk. '
              'If it could, it would substitute its own signing key and then '
              'sign advertised encapsulation keys on that enrollment\'s '
              'behalf — which is exactly what the signature exists to prevent');

      final ownKey = (UpdateVerbBuilder()
            ..atKey = (AtKey()
              ..key = '_apsk.${attacker.enrollmentId}.'
                  '${EnrollmentConstants.perEnrollmentApproved}'
              ..sharedBy = atSign
              ..metadata = (Metadata()..isPublic = true))
            ..value = 'this enrollment may write its own')
          .buildCommand();
      expect(await attackerLookup.executeCommand(ownKey), isNotNull,
          reason: 'the restriction is per-enrollment, not a blanket ban — so '
              'writing its own must succeed on the very same connection');
    } finally {
      await attackerLookup.close();
    }

    // NOTE: a server that errored after writing would satisfy the refusal
    // above and still have handed the attacker the victim's identity.
    final after = await approver.getRemoteSecondary()!.executeCommand(
        'llookup:${apskKeyFor(victim.enrollmentId)}\n',
        auth: true);
    expect(after!.replaceFirst('data:', '').trim(), original,
        reason: 'the victim\'s signing key must be byte-identical to what the '
            'atServer published');
    expect(after, isNot(contains('attacker-substituted-signing-key')),
        reason: 'stated the other way round, so a change in how the record is '
            'serialized cannot make the comparison above vacuous');
  });

  /// The heal path's wire form: an enrollment holding no signing key of its own
  /// gets one at its next start and advertises it by `enroll:update`.
  ///
  /// A single active `rsa2048` key has to travel as the bare string, because
  /// every deployed `_apsk` consumer base64-decodes the value as an RSA key and
  /// fails on JSON. The claim exercised here is the server's: that it honours
  /// `apskLegacy` on an update, not only on the enrolment request.
  test('a healed enrollment advertises its signing key in the bare form',
      () async {
    final keysIo = InMemoryAtKeysIo();
    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      // NOTE: `signingAlgo` is what makes the enrollment ML-DSA, not the
      // preference axis beside it — `enrolAndAuthenticate` mints the APKAM
      // keypair from its own argument and never reads
      // `authenticationKeyAlgorithm`, which is set too so the client's declared
      // and actual algorithms agree. ML-DSA authentication is what makes this a
      // heal at all: with an rsa2048 authentication keypair and no typed
      // signing material, that one keypair IS the data signing keypair, so the
      // mint is correctly a no-op. The posture stays `PqPosture.legacy` so key exchange
      // does not also move to pq, which this test is not about.
      signingAlgo: SigningAlgoType.mldsa65,
      preference: TestUtils.getPreference(atSign,
          authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
          dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048},
          posture: PqPosture.legacy),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      deviceName: 'apsk-heal-$runId',
      atKeysIo: keysIo,
      storage: TestUtils.storage,
    );

    expect((await keysIo.read(atSign)).signingKeysFor(enrolled.enrollmentId),
        isEmpty,
        reason: 'this row is about the heal path, which exists only for an '
            'enrollment holding no signing key of its own');

    final reconciled =
        await SigningKeyMinting(enrolled.client).reconcileSigningKeys();
    expect(reconciled.minted, [SigningAlgoType.rsa2048]);
    expect(reconciled.retired, isEmpty);

    final held = (await keysIo.read(atSign))
        .signingKeysFor(enrolled.enrollmentId)
        .single;
    final published = await approver.getRemoteSecondary()!.executeCommand(
        'llookup:${apskKeyFor(enrolled.enrollmentId)}\n',
        auth: true);
    final value = published!.replaceFirst('data:', '').trim();

    expect(value, held.publicKey,
        reason: 'the record IS the key — the bare form every deployed '
            'consumer base64-decodes. A one-entry JSON array here is '
            'fail-closed but service-breaking for anything already running, '
            'which is the breakage rollout 1 exists to prevent');
    expect(value, isNot(startsWith('{')),
        reason: 'stated the other way round, so this cannot pass on a '
            'serialization that merely contains the key');

    await expectTheHealedPackageIsSignedAgain(enrolled);
  });

  test(
      'an rsa2048 enrollment that heals an ML-DSA signing key signs its key '
      'package again', () async {
    // The rollout path: an existing rsa2048 enrollment whose preference comes
    // to name an ML-DSA signing key. Its package was signed by the rsa2048
    // authentication key, which leaves `_apsk` the moment the enrollment holds
    // a signing key of its own.
    final keysIo = InMemoryAtKeysIo();
    final enrolled = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign,
          dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65},
          posture: PqPosture.legacy),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      deviceName: 'apsk-heal-mldsa-$runId',
      atKeysIo: keysIo,
      storage: TestUtils.storage,
    );

    final reconciled =
        await SigningKeyMinting(enrolled.client).reconcileSigningKeys();
    expect(reconciled.minted, [SigningAlgoType.mldsa65],
        reason: 'precondition: a signing key was minted, so the rsa2048 '
            'authentication key has left `_apsk`');

    await expectTheHealedPackageIsSignedAgain(enrolled);
  });

  test('enroll:listns answers an APKAM connection with the namespace members',
      () async {
    final member = await enrol('listns-member');
    final sharing = AtClientSecretSharing.forClient(member.client);
    await sharing.register();

    // NOTE: this enumeration is refused outright for a client using the
    // atSign's own keys, so it can only be driven from a genuine enrollment.
    final members = await sharing.directory.listForNamespace(namespace);

    expect(members, isNotEmpty,
        reason: 'the enumeration must return the enrollments authorised for '
            'this namespace — an empty answer would silently turn every '
            'fan-out into a no-op');
    expect(members.map((m) => m.enrollmentId), contains(member.enrollmentId),
        reason: 'including this one, which is authorised for the namespace it '
            'is asking about');
  });
}
