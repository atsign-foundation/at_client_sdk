// The substrate and the nskey surface are @experimental; driving them is the
// point of this file.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/nskey_seeding.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// An enrollment with its own keyfile, key package, filing and ring.
typedef _Holder = ({
  EnrolledClient enrolled,
  InMemoryAtKeysIo io,
  AtClientSecretSharing sharing,
  NskeyPrivateFiling filing,
  PublishedNskeyKeyRing ring,
});

/// Who an nskey private reaches: every enrollment with access to its
/// namespace, at the mint and at each later approval, a `*` enrollment
/// included.
///
/// Live because the roster is the atServer's answer: a client pushes to
/// whatever `enroll:listns` lists, so which grants count as access is decided
/// on the far side.
void main() {
  TestUtils.isolateStorage('nskey_conveyance_reach_live_test');
  late AtClient owner;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    // NOTE: the SECOND atSign, as in nskey_rotation_live_test: these tests add
    // enrollments, and every enroll:listns walks the whole roster.
    atSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
    owner = manager.atClient;
    await AtClientSecretSharing.forClient(owner).register();
  });

  // NOTE: unique per run — the atServer refuses a second enrollment carrying an
  // (appName, deviceName) pair that already has one approved.
  final runId = DateTime.now().microsecondsSinceEpoch;

  /// An enrollment granted [grants] and approved by [approver], with its own
  /// keyfile, key package, filing and ring.
  Future<_Holder> holder(String device, Map<String, String> grants,
      {AtClient? approver}) async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final enrolled = await enrolAndAuthenticate(
      approver: approver ?? owner,
      atSign: atSign,
      namespace: namespace,
      // NOTE: a namespace of its own, as an application sets one: approving an
      // enrollment granted only `*`, this holder puts the envelopes there.
      preference:
          TestUtils.getPreference(atSign, posture: legacyPlusPqProviders)
            ..namespace = namespace,
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: '$device-$runId',
      atKeysIo: io,
      namespaces: grants,
      storage: TestUtils.storage,
    );
    final sharing = AtClientSecretSharing.forClient(enrolled.client);
    await sharing.register();
    final filing = NskeyPrivateFiling(keysIo: io, atSign: atSign);
    return (
      enrolled: enrolled,
      io: io,
      sharing: sharing,
      filing: filing,
      ring: PublishedNskeyKeyRing(enrolled.client,
          privateFiling: filing, lockTtl: liveMintLockTtl),
    );
  }

  /// Mints and publishes [ns]'s key as [minter], by the route that conveys it
  /// to the atSign's other enrollments, and answers the published kid.
  Future<String> mint(
      _Holder minter,
      String ns) async {
    expect(
        await NskeySeeding(
          atClient: minter.enrolled.client,
          ring: minter.ring,
          sharing: minter.sharing,
          privateFiling: minter.filing,
        ).seedNamespace(atSign, ns, askRotationPolicy: false),
        isTrue,
        reason: 'the precondition: $ns is fresh, so this call mints it');
    final published = await minter.ring.publishedAdvertisement(atSign, ns);
    expect(published, isNotNull);
    return published!.nskeyKid;
  }

  /// Whether [recipient] has the private for [ns]'s generation [kid] filed,
  /// collecting its envelopes for up to five seconds first.
  Future<bool> received(
      _Holder recipient,
      String ns,
      String kid) async {
    for (var i = 0; i < 20; i++) {
      await recipient.sharing.sweepOnce(fromRemote: true);
      await recipient.filing
          .filePending(recipient.sharing.secretStore.listSecrets());
      if (await recipient.filing.read(ns, kid) != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  test(
      'a key minted in a namespace reaches every enrollment with access to '
      'it, a * enrollment included', () async {
    final base = 'reach$runId';
    final below = 'dev.$base';
    final star = await holder('reach-star', const {'*': 'rw'});
    final reader = await holder('reach-reader', {base: 'r'});
    final stranger = await holder('reach-stranger', {'other$runId': 'rw'});
    final minter = await holder('reach-minter', {base: 'rw'});

    final roster = (await VerbEnrollmentDirectory(minter.enrolled.client)
            .listForNamespace(below))
        .map((member) => member.enrollmentId)
        .toSet();
    expect(roster,
        containsAll([star.enrolled.enrollmentId, reader.enrolled.enrollmentId]),
        reason: 'the atServer lists a * enrollment, and one granted a '
            'namespace above, as members of $below: the roster the mint '
            'pushes to');
    expect(roster, isNot(contains(stranger.enrolled.enrollmentId)),
        reason: 'the control: an enrollment granted only another namespace '
            'is no member, so the list above is a decision and not every '
            'enrollment of the atSign');

    for (final ns in [base, below]) {
      final kid = await mint(minter, ns);
      expect(await received(star, ns, kid), isTrue,
          reason: 'a * enrollment may read $ns, so its mint must reach it');
      expect(await received(reader, ns, kid), isTrue,
          reason: 'read access to $base covers $ns');
    }
    final belowKid = (await minter.ring.publishedAdvertisement(atSign, below))!
        .nskeyKid;
    expect(await received(stranger, below, belowKid), isFalse,
        reason: 'the control: the same push, swept the same way, does not '
            'reach an enrollment without access');
  }, timeout: Timeout(Duration(minutes: 3)));

  test(
      'an approval conveys every key its approver holds that the new '
      'enrollment may read, all of them under *', () async {
    final base = 'approve$runId';
    final below = 'dev.$base';
    final approver =
        await holder('approve-approver', const {'*': 'rw', '__manage': 'rw'});
    final kids = {for (final ns in [base, below]) ns: await mint(approver, ns)};

    // NOTE: approved AFTER the mints, so the mint's push cannot have reached
    // them, and under this posture nothing pulls at start: the approval is
    // the only route either key has to them.
    final star = await holder('approve-star', const {'*': 'rw'},
        approver: approver.enrolled.client);
    final reader = await holder('approve-reader', {base: 'r'},
        approver: approver.enrolled.client);
    final stranger = await holder('approve-stranger', {'other$runId': 'rw'},
        approver: approver.enrolled.client);

    for (final MapEntry(key: ns, value: kid) in kids.entries) {
      expect(await received(star, ns, kid), isTrue,
          reason: 'a * enrollment may read $ns, so its approver must convey '
              'the key it holds for it');
      expect(await received(reader, ns, kid), isTrue,
          reason: 'read access to $base covers $ns');
    }
    expect(await received(stranger, base, kids[base]!), isFalse,
        reason: 'the control: approved by the same approver, holding the '
            'same keys, an enrollment without access is conveyed none');
  }, timeout: Timeout(Duration(minutes: 3)));

  test(
      'an approver that may only read a namespace it holds a key for still '
      'approves, and conveys the keys it may write', () async {
    final readOnly = 'readonly$runId';
    final writable = 'writable$runId';
    final approver = await holder(
        'ro-approver', {readOnly: 'r', '*': 'rw', '__manage': 'rw'});
    final writer = await holder('ro-writer', {readOnly: 'rw'});

    final readOnlyKid = await mint(writer, readOnly);
    expect(await received(approver, readOnly, readOnlyKid), isTrue,
        reason: 'the precondition: read access is access, so the mint '
            'reaches the approver, which now holds a key for a namespace the '
            'atServer will not let it write');
    final writableKid = await mint(approver, writable);

    // NOTE: the approval itself is the assertion. The atServer refuses an
    // envelope this approver writes in the read-only namespace, and an
    // approval that let that refusal escape would throw here, after the
    // approval had landed.
    final star = await holder('ro-star', const {'*': 'rw'},
        approver: approver.enrolled.client);

    expect(await received(star, writable, writableKid), isTrue,
        reason: 'the approver may write $writable, so the approval conveys '
            'its key');
    expect(await received(star, readOnly, readOnlyKid), isFalse,
        reason: 'nothing this approver may write is in $readOnly, so the '
            'approval cannot convey that key; the enrollment asks a holder '
            'that may');
  }, timeout: Timeout(Duration(minutes: 3)));

  test(
      'an approver conveys what the atServer lets it write in a dotted '
      'namespace, which its grant on the last segment decides', () async {
    final base = 'base$runId';
    final narrowReadOnly = 'sub$runId.$base';
    final otherBase = 'otherbase$runId';
    final narrowWritable = 'sub$runId.$otherBase';
    // NOTE: each narrower grant listed first, so a client that takes the first
    // grant matching the namespace reads it, not the grant the atServer reads.
    final approver = await holder('seg-approver', {
      narrowReadOnly: 'r',
      base: 'rw',
      narrowWritable: 'rw',
      otherBase: 'r',
      '*': 'rw',
      '__manage': 'rw',
    });
    final writer = await holder(
        'seg-writer', {narrowReadOnly: 'rw', narrowWritable: 'rw'});

    final readOnlyKid = await mint(writer, narrowReadOnly);
    final writableKid = await mint(writer, narrowWritable);
    expect(await received(approver, narrowReadOnly, readOnlyKid), isTrue,
        reason: 'the precondition: the mint reaches the approver');
    expect(await received(approver, narrowWritable, writableKid), isTrue,
        reason: 'the precondition: the mint reaches the approver');

    final star = await holder('seg-star', const {'*': 'rw'},
        approver: approver.enrolled.client);

    expect(await received(star, narrowReadOnly, readOnlyKid), isTrue,
        reason: 'the atServer reads $narrowReadOnly as $base, where this '
            'approver holds rw, so it accepts the envelope and the approval '
            'conveys the key, whatever the narrower r grant says');
    expect(await received(star, narrowWritable, writableKid), isFalse,
        reason: 'the converse: $otherBase is r for this approver, so the '
            'atServer refuses an envelope in $narrowWritable whatever the '
            'narrower rw grant says, and the approval cannot convey it');
  }, timeout: Timeout(Duration(minutes: 3)));
}
