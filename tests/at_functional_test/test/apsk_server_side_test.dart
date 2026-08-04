// The enrollment fixture is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart' show EnrollmentConstants;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The atServer's half of advertised-key verification.
///
/// The whole parent-signs / child-publishes arrangement rests on two
/// properties of the atServer that the client cannot provide for itself, and
/// which had never been watched:
///
/// - **`_apsk` exists without the enrolling client publishing it.** The
///   atServer writes it at approval. If it did not, a verifier meeting a
///   freshly approved enrollment would find no signing key to check its
///   advertised encapsulation key against, and would have to either reject a
///   legitimate peer or trust it unverified.
/// - **`_apsk` is write-restricted to its own enrollment.** If any enrollment
///   could overwrite another's, it could substitute its own signing key and
///   then sign an advertised encapsulation key of its choosing on that
///   enrollment's behalf — which is the entire attack the signature exists to
///   stop.
///
/// Both need two genuine enrollments to test at all, since the interesting
/// case is one enrollment reaching for another's record.
void main() {
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';
  const rootDomain = 'vip.ve.atsign.zone';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  final runId = DateTime.now().microsecondsSinceEpoch;

  Future<EnrolledClient> enrol(String device) => enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign),
        rootDomain: rootDomain,
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
      );

  String apskKeyFor(String enrollmentId) =>
      'public:_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
      '$atSign';

  test('the atServer publishes _apsk itself, and refuses a cross-enrollment '
      'overwrite', () async {
    final victim = await enrol('apsk-victim');
    final attacker = await enrol('apsk-attacker');

    expect(attacker.enrollmentId, isNot(victim.enrollmentId),
        reason: 'the attack under test is one enrollment reaching for '
            'another\'s record; with one enrollment there is nothing to reach '
            'for and the refusal below would be meaningless');

    // 1. Present without the victim ever having published it. Nothing in this
    //    test wrote it — the atServer did, at approval.
    final published = await approver
        .getRemoteSecondary()!
        .executeCommand('llookup:${apskKeyFor(victim.enrollmentId)}\n',
            auth: true);
    expect(published, isNotNull);
    expect(published, contains('data:'),
        reason: 'a verifier meeting a freshly approved enrollment must find '
            'its signing key already there. Without it the verifier can only '
            'reject a legitimate peer or trust one unverified');
    final original = published!.replaceFirst('data:', '').trim();
    expect(original, isNotEmpty);

    // 2. The attacker, authenticated as its own enrollment, tries to overwrite
    //    the victim's signing key with something it controls.
    final attackerLookup =
        AtLookupImpl(atSign, rootDomain, TestUtils.rootServerPort)
          ..enrollmentId = attacker.enrollmentId
          ..atChops = attacker.client.atChops;

    try {
      // Control: this connection is genuinely authenticated as the attacker,
      // so the refusal below is an authorization decision and not a broken
      // connection or an unauthenticated caller.
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

      // Matched on the reason, naming both the asking enrollment and the key
      // it reached for. A bare throwsA would be satisfied by a malformed verb
      // and the test would be green for the absence of an effect.
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

      // Control, on the same connection: the attacker CAN write its OWN
      // _apsk-shaped key. Without this, the refusal above is equally explained
      // by nobody being allowed to write _apsk at all, which would be a
      // different (and much less interesting) property.
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

    // 3. And the record is unchanged. A server that errored after writing
    //    would satisfy the check above and still have handed the attacker the
    //    victim's identity.
    final after = await approver
        .getRemoteSecondary()!
        .executeCommand('llookup:${apskKeyFor(victim.enrollmentId)}\n',
            auth: true);
    expect(after!.replaceFirst('data:', '').trim(), original,
        reason: 'the victim\'s signing key must be byte-identical to what the '
            'atServer published');
    expect(after, isNot(contains('attacker-substituted-signing-key')),
        reason: 'stated the other way round, so a change in how the record is '
            'serialized cannot make the comparison above vacuous');
  });

  test('enroll:listns answers an APKAM connection with the namespace members',
      () async {
    final member = await enrol('listns-member');
    final sharing = AtClientSecretSharing.forClient(member.client);
    await sharing.register();

    // The live enumeration the substrate's push and pull both depend on. It is
    // refused outright for a client using the atSign's own keys, so until the
    // two-enrollment fixture existed this could not be driven at all.
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
