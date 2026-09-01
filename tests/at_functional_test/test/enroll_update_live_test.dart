// The enrollment fixture is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show
        AtChopsImpl,
        AtChopsKeys,
        AtChopsUtil,
        AtEncryptionKeyPair,
        AtPkamKeyPair,
        AtSigningInput,
        AtSigningMode,
        HashingAlgoType,
        SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart'
    show AtLookUp, AtLookupImpl, AtLookUpException;
import 'package:at_commons/at_commons.dart' show EnrollmentConstants;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// `enroll:update` against a live atServer — UC-G1.10 to UC-G1.13
/// (`docs/projects/pq/acceptance.md` section 16.4).
///
/// **These rows cannot be proven anywhere else.** Every one of them is the
/// atServer saying no, and a mocked `AtLookUp` that accepts whatever it is
/// handed makes the refusal's presence and its absence indistinguishable — the
/// at_auth unit suite stubs `executeCommand` to succeed, so the guards below
/// are invisible there. What is asserted here is the other side's behaviour,
/// so the other side has to be running.
///
/// Every enrollment is created with a run-unique device name. Enrollment state
/// is one-shot: an `(appName, deviceName)` pair that is already approved is
/// refused, so a file that hard-codes one passes on a fresh virtualenv and
/// fails on the second run against the same one.
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
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo,
            posture: legacyPlusPqProviders);
    approver = manager.atClient;
  });

  final runId = DateTime.now().microsecondsSinceEpoch;

  /// The enrolled client's own authenticated connection. `EnrolledClient`
  /// exposes the AtClient rather than a lookup, and the lookup is what carries
  /// the enrollment id the atServer judges self-only against.
  AtLookUp lookupOf(EnrolledClient c) =>
      c.client.getRemoteSecondary()!.atLookUp;

  Future<EnrolledClient> enrol(String device) => enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy),
        rootDomain: rootDomain,
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
      );

  /// The enrollment record as the atServer holds it, read back rather than
  /// remembered: what these rows assert is what the record says afterwards,
  /// and a client's idea of what it sent is not that.
  Future<Map<String, dynamic>> fetch(EnrolledClient client) async {
    final response = await lookupOf(client).executeCommand(
        'enroll:fetch:{"enrollmentId":"${client.enrollmentId}"}\n',
        auth: true);
    return jsonDecode(response!.replaceFirst(RegExp(r'^data:'), ''))
        as Map<String, dynamic>;
  }

  String apskKeyFor(String enrollmentId) =>
      'public:_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
      '$atSign';

  Future<String?> readApsk(EnrolledClient client) async {
    try {
      final response = await lookupOf(client)
          .executeCommand('llookup:${apskKeyFor(client.enrollmentId)}\n',
              auth: true);
      if (response == null || !response.startsWith('data:')) return null;
      return response.replaceFirst('data:', '').trim();
    } on Object {
      return null;
    }
  }

  /// Whether [privateKey] can authenticate as this enrollment on a FRESH
  /// connection — the only place a rotation is observable, since the record is
  /// never handed back with its public key in it.
  ///
  /// A fresh connection every time: the enrolled client's own is already
  /// authenticated, so reusing it would answer about a past handshake.
  Future<bool> authenticatesWith(EnrolledClient client, String privateKey) async {
    final lookup = AtLookupImpl(atSign, rootDomain, TestUtils.rootServerPort);
    try {
      final challenge = (await lookup.executeCommand('from:$atSign\n'))!
          .trim()
          .replaceFirst(RegExp(r'^data:'), '');
      final chops = AtChopsImpl(AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            client.keys.defaultEncryptionPublicKey!.toString(), ''),
        AtPkamKeyPair.create('', privateKey),
      ));
      final signature = chops
          .sign(AtSigningInput(challenge)
            ..signingAlgoType = SigningAlgoType.rsa2048
            ..hashingAlgoType = HashingAlgoType.sha256
            ..signingMode = AtSigningMode.pkam)
          .result;
      final response = await lookup.executeCommand((PkamVerbBuilder()
            ..signingAlgo = SigningAlgoType.rsa2048.name
            ..hashingAlgo = HashingAlgoType.sha256.name
            ..enrollmentlId = client.enrollmentId
            ..signature = signature)
          .buildCommand());
      return response != null && response.contains('success');
    } on Object {
      // A refusal arrives as an exception on some paths and as a non-success
      // string on others; both mean the same thing here.
      return false;
    } finally {
      await lookup.close();
    }
  }

  /// The public keys an `_apsk` value advertises, whichever of its two shapes
  /// it is in — the bare RSA string, or the JSON array.
  ///
  /// Normalising here rather than pinning one spelling: both are legitimate
  /// forms of the same record and the writer picks between them by what the
  /// entry list holds, so a test that pinned the spelling would be asserting a
  /// property of the publisher's timing.
  Set<String> advertisedKeys(String? value) {
    if (value == null || value.isEmpty) return const {};
    if (!value.startsWith('{')) return {value};
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return {
      for (final k in (decoded['keys'] as List).cast<Map<String, dynamic>>())
        k['pub'] as String
    };
  }

  ({String publicKey, String privateKey}) freshApkamPair() {
    final pair = AtChopsUtil.generateAtPkamKeyPair();
    return (
      publicKey: pair.atPublicKey.publicKey,
      privateKey: pair.atPrivateKey.privateKey
    );
  }

  test('UC-G1.10 · rekey keeps the enrollment id', () async {
    final client = await enrol('g110-rekey');
    final before = await fetch(client);
    final oldPrivateKey = client.keys.apkamPrivateKey!.toString();
    final apskBefore = await readApsk(client);
    final fresh = freshApkamPair();

    final response = await AtEnrollment.create().update(
        EnrollmentUpdateRequest(
          enrollmentId: client.enrollmentId,
          apkamPublicKey: fresh.publicKey,
          apkamPrivateKey: fresh.privateKey,
          signingAlgo: SigningAlgoType.rsa2048,
        ),
        lookupOf(client));

    expect(response.enrollmentId, client.enrollmentId,
        reason: 'a rekey amends the record it names; a new id would be a new '
            'enrollment, which is the whole thing this row denies');

    final after = await fetch(client);

    // The key moved — asserted where it SHOWS rather than where it is stored.
    //
    // `enroll:fetch` returns exactly five fields (appName, deviceName,
    // namespace, encryptedAPKAMSymmetricKey, status) and `apkamPublicKey` is
    // not among them, so the record cannot be read back for it. What the
    // rotation is FOR is which key authenticates, so that is what this checks:
    // the new private half signs a `from:` challenge the atServer accepts, and
    // the old one no longer does.
    expect(await authenticatesWith(client, fresh.privateKey), isTrue,
        reason: 'the request must actually have installed the new key — '
            'without this the row passes for a server that accepted it and '
            'did nothing');
    expect(await authenticatesWith(client, oldPrivateKey), isFalse,
        reason: 'and the old key must stop working, or the rotation added a '
            'second valid credential rather than replacing one');

    // And nothing else moved.
    for (final field in ['appName', 'deviceName', 'namespace', 'status']) {
      expect(after[field], before[field],
          reason: '$field must survive a rekey untouched — a rotation that '
              'could also widen a grant would be a privilege escalation with '
              'a signature on it');
    }

    // The corrected clause. This row claimed "_apsk is rewritten from the
    // request's apsk" until 2026-08-18, which its own When forbids: a rotation
    // names three fields and apsk is not one of them, so the client sends none
    // and the record keeps advertising the key it already did.
    //
    // Compared by KEY rather than by the value's spelling, deliberately. The
    // record has a second writer: this client's own start-time heal path
    // republishes a lone active rsa2048 signing key in the BARE form that
    // every deployed consumer parses, so an advertisement written as the array
    // at approval becomes the bare string shortly afterwards — same key, two
    // spellings, and which one is on the record at any instant is a race with
    // the client's startup rather than anything the rekey did. What the row
    // actually promises is that the rekey does not unpublish the signing key
    // peers verify against, and that is what this asserts.
    expect(advertisedKeys(await readApsk(client)), advertisedKeys(apskBefore),
        reason: 'a request that named no apsk must not change WHICH key is '
            'advertised, or a rekey would silently unpublish the signing key '
            'every peer verifies against');
  });

  test('UC-G1.11 · proof of possession is required', () async {
    final client = await enrol('g111-pop');
    final fresh = freshApkamPair();

    Future<String?> sendWith(String? signature) {
      final builder = EnrollVerbBuilder()
        ..enrollmentId = client.enrollmentId
        ..operation = EnrollOperationEnum.update
        ..apkamPublicKey = fresh.publicKey
        ..signingAlgo = SigningAlgoType.rsa2048.name
        ..apkamPublicKeySignature = signature;
      // Built by hand rather than through EnrollmentUpdateRequest, because the
      // request composes a correct signature and cannot express the two arms
      // this row exists to check.
      return lookupOf(client).executeCommand(builder.buildCommand(), auth: true);
    }

    // Arm 1: no proof at all.
    await expectLater(
        sendWith(null),
        throwsA(isA<AtLookUpException>().having((e) => e.errorMessage,
            'errorMessage', contains('requires apkamPublicKeySignature'))),
        reason: 'a rekey with no possession proof must be refused: the '
            'connection proves possession of the CURRENT key and nothing else '
            'proves possession of the new one. Asserted on the atServer\'s '
            'own message rather than on any throw — this is a live test, so a '
            'connection reset, a timeout and a malformed command all throw '
            'too, and a bare isA<Object>() cannot tell the guard firing from '
            'the call failing');

    // Arm 2: a proof, but by the wrong key. This is the arm that discriminates
    // — a server that merely checked the field was present would pass arm 1's
    // fix and fail here.
    final other = freshApkamPair();
    // Signed by the production helper, with the WRONG private key: a proof
    // over the right bytes that the key being installed did not make. Rolling
    // the signature by hand here would test this file's crypto rather than
    // the atServer's check.
    final wrong = apkamPossessionSignature(
      enrollmentId: client.enrollmentId,
      apkamPublicKey: fresh.publicKey,
      apkamPrivateKey: other.privateKey,
      signingAlgo: SigningAlgoType.rsa2048,
    );
    await expectLater(
        sendWith(wrong),
        throwsA(isA<AtLookUpException>().having(
            (e) => e.errorMessage,
            'errorMessage',
            contains(
                'does not verify against the apkamPublicKey being installed'))),
        reason: 'a proof signed by a key other than the one being installed '
            'must be refused, or an authenticated-but-compromised client '
            'could install a key whose private half someone else holds. The '
            'message differs from arm 1\'s, so the two arms are distinguished '
            'by which check refused them rather than only by both throwing');

    // The record is unchanged. Checked where it SHOWS: enroll:fetch returns
    // five fields and apkamPublicKey is not among them, so "unchanged" means
    // the key that authenticated before still does, and neither refused
    // request installed the one it carried. A server that refused AFTER
    // writing would pass without this, and that outcome installs a key whose
    // private half the caller may not hold.
    //
    // ⚠️ It has to sit HERE, before the valid-proof control below, which
    // rewrites the record deliberately.
    expect(
        await authenticatesWith(
            client, client.keys.apkamPrivateKey!.toString()),
        isTrue,
        reason: 'the enrollment must still authenticate with the key it had, '
            'or a refused rekey took its credential away');
    expect(await authenticatesWith(client, fresh.privateKey), isFalse,
        reason: 'and the key both refusals tried to install must not work — a '
            'refusal that had already written is worse than no guard');

    // The control. Without it both refusals above are satisfied by a server
    // that refuses every update, and this row would prove nothing about the
    // proof specifically.
    final ok = await AtEnrollment.create().update(
        EnrollmentUpdateRequest(
          enrollmentId: client.enrollmentId,
          apkamPublicKey: fresh.publicKey,
          apkamPrivateKey: fresh.privateKey,
          signingAlgo: SigningAlgoType.rsa2048,
        ),
        lookupOf(client));
    expect(ok.enrollmentId, client.enrollmentId,
        reason: 'the same rekey with a valid proof must succeed, or the two '
            'refusals above are measuring a server that says no to '
            'everything');
  });

  test('UC-G1.12 · namespaces stay out of reach', () async {
    final client = await enrol('g112-ns');
    final before = await fetch(client);

    // ⚠️ The client half is NOT asserted here, and it used to be — by
    // building an `EnrollVerbBuilder` that named no namespaces and observing
    // that its command carried none. That builder does carry a `namespaces`
    // field, because `enroll:request` needs one, so the assertion said only
    // that this test had not set it: it would have stayed green for a
    // production composer that filled it in. It is asserted properly in
    // at_auth's `enrollment_update_test.dart`, over the command
    // `AtEnrollmentImpl().update` actually emits for a request naming every
    // field it has, as a closed set of keys.
    //
    // The server half: the privilege-escalation guard, refused by its own
    // named error rather than by a generic failure.
    //
    // ⛔ **The request must name a VALID field alongside `namespaces`, or it
    // never reaches that guard**, so do not simplify it down to the illegal
    // field alone. A request naming nothing the verb recognises is refused by
    // an EARLIER well-formedness check:
    //
    //   AT0022 · enroll:update must name at least one of apkamPublicKey,
    //            signingAlgo, apsk, apskLegacy or metadata
    //
    // which says nothing about namespaces. Stripped that far, the arm varies
    // two things at once — it adds `namespaces` AND omits every field the verb
    // knows — so it cannot tell "namespaces is refused" from "namespaces is
    // ignored and the command was empty", and removing the escalation guard
    // altogether leaves it green. The `metadata` entry below is what keeps the
    // request well-formed, so the namespaces entry is the only thing left that
    // can refuse it.
    final raw = 'enroll:update:${jsonEncode({
          'enrollmentId': client.enrollmentId,
          'metadata': {'note': 'g112'},
          'namespaces': {'__manage': 'rw'},
        })}\n';
    await expectLater(
        lookupOf(client).executeCommand(raw, auth: true),
        throwsA(isA<AtLookUpException>().having((e) => e.errorMessage,
            'errorMessage', contains('cannot change namespaces'))),
        reason: 'an enrollment must not be able to widen its own grant, and '
            'the refusal must be THAT guard — the metadata beside it is a '
            'field the verb accepts, so the request is well-formed and only '
            'the namespaces entry can be what refuses it');

    // And the earlier check, pinned as its own arm so the two refusals stay
    // distinguishable. Without it, a change that collapsed both into one
    // message would go unnoticed.
    final bare = 'enroll:update:${jsonEncode({
          'enrollmentId': client.enrollmentId,
          'namespaces': {'__manage': 'rw'},
        })}\n';
    await expectLater(
        lookupOf(client).executeCommand(bare, auth: true),
        throwsA(isA<AtLookUpException>().having((e) => e.errorMessage,
            'errorMessage', contains('must name at least one of'))),
        reason: 'a request naming only namespaces is refused for naming '
            'nothing the verb knows, which is a different refusal from the '
            'one above and must not be mistaken for it');

    expect((await fetch(client))['namespace'], before['namespace'],
        reason: 'and the record is unchanged — a refusal that had already '
            'written would be worse than no guard at all');
  });

  test('UC-G1.13 · self-only', () async {
    final mine = await enrol('g113-self');
    final other = await enrol('g113-other');

    // Arm 1: one approved enrollment reaching for another's record. The
    // self-only check runs BEFORE the target record is fetched, which is why
    // this row promises only self-only: the target's approval state is never
    // read on this path, so no approved-only guard can fire here.
    final fresh = freshApkamPair();
    await expectLater(
        AtEnrollment.create().update(
            EnrollmentUpdateRequest(
              enrollmentId: other.enrollmentId,
              apkamPublicKey: fresh.publicKey,
              apkamPrivateKey: fresh.privateKey,
              signingAlgo: SigningAlgoType.rsa2048,
            ),
            lookupOf(mine)),
        throwsA(isA<AtLookUpException>().having(
            (e) => e.errorMessage,
            'errorMessage',
            allOf(contains('self-only'), contains(mine.enrollmentId),
                contains(other.enrollmentId)))),
        reason: 'E1 must not amend E2: the whole point of a self-only verb is '
            'that holding one enrollment grants nothing over another. The '
            'message must name BOTH enrollments — the one that asked and the '
            'one it reached for — so a refusal for any other reason, or one '
            'about the wrong pair, cannot satisfy it');

    // Arm 2: a legacy PKAM connection. It carries the housekeeping enrollment
    // `primary` — an atServer creates that record on the first legacy
    // authentication — so it is refused as a NAMED enrollment rather than as
    // an anonymous owner. That naming is what having an enrollment record
    // buys a legacy connection, and it is only observable end to end.
    //
    // ⚠️ This arm used to reach a connection carrying NO enrollment id, and
    // that state is no longer reachable over legacy PKAM. It still exists —
    // CRAM produces it, and the self-only refusal is an explicit exception to
    // `isAuthorized` treating an absent enrollment id as full permissions, so
    // an id-less connection is the one that default would wave through.
    // It is pinned in at_server rather than here, in
    // `at_secondary_server/test/enroll_verb_test.dart`, by the test named
    // "an ID-LESS connection is refused, not waved through" — look in that
    // file if the name has moved. Not pinned live because CRAM authentication
    // DELETES the atSign's stored secret on success, so reaching it costs a
    // dedicated atSign that nothing else in this pack may ever CRAM.
    await expectLater(
        AtEnrollment.create().update(
            EnrollmentUpdateRequest(
              enrollmentId: mine.enrollmentId,
              apkamPublicKey: fresh.publicKey,
              apkamPrivateKey: fresh.privateKey,
              signingAlgo: SigningAlgoType.rsa2048,
            ),
            approver.getRemoteSecondary()!.atLookUp),
        throwsA(isA<AtLookUpException>().having(
            (e) => e.errorMessage,
            'errorMessage',
            allOf(contains('self-only'), contains('primary'),
                contains(mine.enrollmentId)))),
        reason: 'a legacy connection is refused as the enrollment it actually '
            'authenticated as. Asserting the literal `primary` pins more than '
            '"the owner" did, because it names a record the caller can go and '
            'read — and it pins that a legacy connection now HAS one, which '
            'is the thing that changed');

    // The control: the same request on its OWN connection succeeds, so both
    // refusals are about who asked rather than about the request being
    // malformed.
    final ok = await AtEnrollment.create().update(
        EnrollmentUpdateRequest(
          enrollmentId: mine.enrollmentId,
          apkamPublicKey: fresh.publicKey,
          apkamPrivateKey: fresh.privateKey,
          signingAlgo: SigningAlgoType.rsa2048,
        ),
        lookupOf(mine));
    expect(ok.enrollmentId, mine.enrollmentId);
  });
}
