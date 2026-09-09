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

/// `enroll:update` against a live atServer — UC-G1.10 to UC-G1.13.
///
/// Every enrollment is created with a run-unique device name: enrollment state
/// is one-shot, so an `(appName, deviceName)` pair that is already approved is
/// refused on a second run against the same virtualenv.
void main() {
  TestUtils.isolateStorage('enroll_update_live_test');
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

  /// The enrolled client's own authenticated connection, which carries the
  /// enrollment id the atServer judges self-only against.
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
    storage: TestUtils.storage,
  );

  /// The enrollment record as the atServer holds it, read back rather than
  /// remembered.
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
  /// never handed back with its public key in it. The enrolled client's own
  /// connection is already authenticated, so reusing it would answer about a
  /// past handshake.
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
      return false;
    } finally {
      await lookup.close();
    }
  }

  /// The public keys an `_apsk` value advertises, whichever of its two shapes
  /// it is in — the bare RSA string, or the JSON array.
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

    // NOTE: `enroll:fetch` never returns apkamPublicKey, so a rotation is only
    // observable through which key authenticates.
    expect(await authenticatesWith(client, fresh.privateKey), isTrue,
        reason: 'the request must actually have installed the new key — '
            'without this the row passes for a server that accepted it and '
            'did nothing');
    expect(await authenticatesWith(client, oldPrivateKey), isFalse,
        reason: 'and the old key must stop working, or the rotation added a '
            'second valid credential rather than replacing one');

    for (final field in ['appName', 'deviceName', 'namespace', 'status']) {
      expect(after[field], before[field],
          reason: '$field must survive a rekey untouched — a rotation that '
              'could also widen a grant would be a privilege escalation with '
              'a signature on it');
    }

    // NOTE: compared by key rather than by the value's spelling — the client's
    // own start-time heal path rewrites the same key from the JSON array into
    // the bare form, so the spelling on the record races with startup.
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
      // NOTE: built by hand because EnrollmentUpdateRequest always composes a
      // valid signature, which neither arm below can use.
      return lookupOf(client).executeCommand(builder.buildCommand(), auth: true);
    }

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

    final other = freshApkamPair();
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

    // NOTE: these two must stay above the valid-proof control below, which
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

    // NOTE: the request must name a field the verb accepts — the `metadata`
    // entry — alongside `namespaces`, or an earlier well-formedness check
    // (AT0022) refuses it and the escalation guard is never reached.
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

    // A legacy PKAM connection carries the housekeeping enrollment `primary`,
    // so it is refused as a named enrollment rather than as an anonymous owner.
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
