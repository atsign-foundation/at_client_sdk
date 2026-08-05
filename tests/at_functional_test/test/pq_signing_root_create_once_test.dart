// The signing-root surface is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Create-once, observed on the wire rather than inferred from the metadata.
///
/// `PqSigningRoot` sets `immutable = true` and the design leans on the
/// atServer honouring it: the root never rotates, so a second one is not
/// untidy but unrecoverable — half an atSign's enrollments would chain to a
/// root the other half rejected, with no later event able to reconcile them.
/// That is a cross-tier assumption of exactly the kind this branch has had
/// wrong twice, so it is worth watching the atServer refuse.
///
/// The assertion that carries the weight is not that the second write errors —
/// it is that the stored value is **unchanged afterwards**. A server that
/// accepted the write and returned an error would satisfy the first check and
/// still have destroyed the atSign's root.
///
/// The companion claim is that `public:__nskey.<ns>@owner` is deliberately
/// **not** create-once: nskey rotation has to overwrite it. Asserting both in
/// one file keeps the contrast visible, because "immutable" applied to the
/// wrong one of these two records would break rotation instead.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'wavi';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    atClient = manager.atClient;
  });

  Future<String> remote(String command) async =>
      (await atClient
          .getRemoteSecondary()!
          .executeCommand(command, auth: true)) ??
      '';

  /// The published root's raw value, or null when nothing is published.
  Future<String?> publishedRoot() async {
    try {
      final response =
          await remote('llookup:public:${PqSigningRoot.recordName}$atSign\n');
      final trimmed = response.replaceFirst('data:', '').trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  test('a second signing-root create is refused, and changes nothing',
      () async {
    // The suite order is not fixed and another file may already have anchored
    // this atSign, so establish the precondition rather than assuming it: what
    // is under test is that a root, once present, cannot be replaced — not who
    // put it there.
    var existing = await publishedRoot();
    if (existing == null) {
      final builder = UpdateVerbBuilder()
        ..atKey = PqSigningRoot(atClient).keyFor(atSign)
        // Valid base64, though not a real key — mintIfAbsent's absence check
        // decodes whatever record it finds, and a value it cannot decode
        // would turn every later mint on this atSign into a parse error.
        ..value = jsonEncode({
          'v': PqSigningRoot.currentVersion,
          'keys': [base64Encode(utf8.encode('the-first-root'))],
          'successor': null,
        });
      await atClient.getRemoteSecondary()!.executeVerb(builder, sync: true);
      existing = await publishedRoot();
    }

    expect(existing, isNotNull,
        reason: 'nothing below tests create-once unless a root exists to be '
            'protected — this is the precondition, not the assertion');
    expect(existing, contains('keys'),
        reason: 'and it must be the real record shape, or the "unchanged" '
            'check below could pass on a value nobody would miss');

    // The second create, with a deliberately different value so an accepted
    // overwrite is unmistakable. Picking a value that differs is the whole
    // reason this can distinguish "refused" from "silently re-wrote the same
    // thing".
    final second = UpdateVerbBuilder()
      ..atKey = PqSigningRoot(atClient).keyFor(atSign)
      ..value = jsonEncode({
        'v': PqSigningRoot.currentVersion,
        'keys': ['a-second-root-that-must-never-land'],
        'successor': null,
      });

    // Named, not `anything`: a bare throwsA would pass if the write failed for
    // an unrelated reason — a malformed verb, an auth problem — and the test
    // would then be green for the absence of the effect rather than for the
    // guard.
    await expectLater(
        atClient.getRemoteSecondary()!.executeVerb(second, sync: true),
        throwsA(predicate((e) =>
            e is IllegalStateException &&
            '$e'.contains('Immutable records may not be updated'))),
        reason: 'the atServer must refuse a second create, and refuse it FOR '
            'immutability; an accepted one gives the atSign two roots and no '
            'way back');

    // Control: the same client, the same verb, a public key differing only in
    // that it is mutable — accepted twice. Without this, the refusal above
    // could be this client being unable to write public keys at all.
    final mutable = AtKey()
      ..key = 'createoncecontrol${DateTime.now().microsecondsSinceEpoch}'
      ..sharedBy = atSign
      ..metadata = (Metadata()..isPublic = true);
    for (final value in ['first', 'second']) {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = mutable
            ..value = value,
          sync: true);
    }

    // The assertion that actually matters.
    expect(await publishedRoot(), existing,
        reason: 'the stored root must be byte-identical to what was there '
            'before. A server that errored AFTER writing would pass the check '
            'above and still have destroyed the chain every enrollment on '
            'this atSign verifies against');
    expect(await publishedRoot(),
        isNot(contains('a-second-root-that-must-never-land')),
        reason: 'stated the other way round, so a change in how the record is '
            'serialized cannot make the comparison above vacuous');
  });

  test('the enrollment that loses the create does not mint a second root',
      () async {
    // The atServer guard above is only half the story. What the losing CLIENT
    // does is the other half: it must return empty-handed — and holding
    // nothing — so its caller knows to request the root from a holder. A
    // loser that treated the loss as an error to retry, or that minted its
    // own, would produce exactly the split-root state the immutability is
    // there to prevent; one that kept a filed private would read as "already
    // holding the root" forever and never ask.
    //
    // Against a live atSign with a root already published, the loss is met at
    // the absence check — nothing reaches the atServer and nothing is filed.
    // The narrower true race, where two mints both find the record absent and
    // one meets the refusal, is unit-covered with the refusal mocked; the
    // refusal itself is what the test above watches the live atServer issue.
    final loserKeys = InMemoryAtKeysIo();
    await loserKeys.write(atSign, AtKeys());
    final root = PqSigningRoot(atClient, keysIo: loserKeys);

    final before = await publishedRoot();
    expect(before, isNotNull,
        reason: 'a root is already published by the test above, so this call '
            'is the LOSER by construction — that is the case under test');

    final minted = await root.mintIfAbsent(isFullyPrivileged: true);

    expect(minted, isNull,
        reason: 'the loser must report that it did not mint. A non-null return '
            'here says "I published the root", and its caller would anchor '
            'every later signature to a key the atSign never accepted');
    expect(await publishedRoot(), before,
        reason: 'and it must not have disturbed the published record');
    expect(await root.privateHalf(atSign), isNull,
        reason: 'the loser must hold nothing afterwards: an active private '
            'here would satisfy the pull\'s "already holding it" guard, and '
            'the one heal a loser has — being given the real private by a '
            'holder — would never fire');

    // A namespace-scoped enrollment must not even attempt it — the root
    // vouches for every enrollment, so minting it is not a scoped operation.
    expect(await root.mintIfAbsent(isFullyPrivileged: false), isNull);
  });

  test('the published nskey is mutable, because rotation depends on it',
      () async {
    // The control for the test above: same atSign, same public namespace, and
    // the opposite requirement. If "immutable" ever migrated onto this record,
    // the create-once test would still pass while nskey rotation silently
    // stopped working.
    final ns = 'rot${DateTime.now().microsecondsSinceEpoch}.$namespace';
    final ring = PublishedNskeyKeyRing(atClient);

    final first = await ring.mintAndPublish(ns);
    final second = await ring.mintAndPublish(ns);

    expect(second.nskeyKid, isNot(first.nskeyKid),
        reason: 'a rotation mints a NEW generation; if these match, the second '
            'publish was a no-op and this proves nothing about mutability');

    final resolved =
        await PublishedNskeyKeyRing(atClient).currentPublic(atSign, ns);
    expect(resolved?.nskeyKid, second.nskeyKid,
        reason: 'the advertisement must now name the new generation — an '
            'immutable nskey record would have pinned peers to the old key '
            'forever, which is rotation failing closed and silently');
  });
}
