// The enrollment key-package surface is @experimental; driving it is the point.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope, verifyEnvelope;
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:test/test.dart';

import 'test_utils.dart';

/// Key package amendment against a live atServer — UC-A2.5 and UC-A2.6.
///
/// NOTE: every enrollment uses a run-unique device name. Enrollment state is
/// one-shot, so an `(appName, deviceName)` pair that is already approved is
/// refused, and a hard-coded one passes on a fresh virtualenv and fails on the
/// second run against the same one.
void main() {
  TestUtils.isolateStorage('key_package_amendment_live_test');
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';
  const rootDomain = 'vip.ve.atsign.zone';

  final runId = DateTime.now().microsecondsSinceEpoch;

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
  });

  AtLookUp lookupOf(EnrolledClient c) =>
      c.client.getRemoteSecondary()!.atLookUp;

  /// The keyfile each enrolment was given, so an enrollment can be re-opened.
  final keyfiles = <String, InMemoryAtKeysIo>{};

  /// Enrols and authenticates a client whose preference advertises
  /// [algorithms].
  Future<EnrolledClient> enrol(String device, List<String> algorithms) async {
    final keysIo = InMemoryAtKeysIo();
    keyfiles[device] = keysIo;
    return enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: namespace,
      preference: TestUtils.getPreference(atSign,
          keyEstablishmentAlgorithms: algorithms,
          posture: legacyPlusPqProviders),
      rootDomain: rootDomain,
      rootPort: TestUtils.rootServerPort,
      deviceName: '$device-$runId',
      atKeysIo: keysIo,
      storage: TestUtils.storage,
    );
  }

  /// The key package the atServer is serving for [client], verified against
  /// the enrollment's own advertised signing key the way a peer verifies it.
  ///
  /// NOTE: read through `enroll:listns`, not `enroll:fetch` — `enroll:fetch`
  /// returns five fields and `metadata` is not among them, and `listns` is the
  /// verb a peer discovers a key package through.
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
    final envelope = SignedEnvelope.fromJson((metadata as Map)
        .cast<String, dynamic>()['keyPackage'] as Map<String, dynamic>);
    // NOTE: against the `_apsk` the atServer is SERVING, not a key this test
    // holds. A peer has only the record, and a locally remembered key would
    // still pass if the amendment published an advertisement that disagreed
    // with what it signed.
    final apskKey = 'public:_apsk.${client.enrollmentId}.'
        '${EnrollmentConstants.perEnrollmentApproved}$atSign';
    final apsk =
        await lookupOf(client).executeCommand('llookup:$apskKey\n', auth: true);
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
    // Two arms rather than a before-and-after on one client: the PQ startup is
    // fired unawaited by the client's init, so a "before" read can land either
    // side of the amendment. Each arm is read only once its startup has
    // completed, and the varied thing is the configured list alone.
    final single = await enrol('a25-single', const [SecretSharingAlgos.xWing]);
    final both = await enrol('a25-amend',
        const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);

    await (single.client as AtClientImpl).pqBootstrap!.startupComplete;
    await (both.client as AtClientImpl).pqBootstrap!.startupComplete;

    // Control: a client whose list matches what it was created with leaves the
    // record alone.
    final unchanged = await servedPackage(single);
    expect(unchanged.keys, hasLength(1),
        reason: 'an enrollment is created advertising one key, and a startup '
            'that finds nothing missing must not rewrite the record');
    expect(unchanged.keys.single.alg, SecretSharingAlgos.xWing);

    final amended = await servedPackage(both);
    expect(amended.keys.map((k) => k.alg).toSet(),
        {SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024},
        reason: 'a package can now gain a key — the claim KE-2 existed for. '
            'The control arm shows both started from one');

    // An amendment that moved the enrollment would strand every secret already
    // sealed to the old kpid.
    final original = amended.keys.where((k) => k.kid == both.kpid).toList();
    expect(original, hasLength(1),
        reason: 'the key the enrollment advertised at creation keeps its '
            'address — EnrolledClient.kpid is what secrets were sealed to');
    expect(original.single.status, KeyEntryStatus.active);

    expect(
        amended.suites,
        containsAll(SecretSharingAlgos.openableSuitesForAll(
            const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024])),
        reason: 'the suites list covers both KEMs, derived from the keys');

    // Reaching here is itself an assertion: servedPackage throws if the
    // amended package no longer verifies against this enrollment's _apsk.
  });

  test('UC-A2.6 · only the enrollment itself may amend its metadata', () async {
    final mine = await enrol('a26-mine', const [SecretSharingAlgos.xWing]);
    final other = await enrol('a26-other', const [SecretSharingAlgos.xWing]);

    // A well-formed metadata amendment, so that every refusal below is about
    // WHO asked rather than about the request being malformed.
    //
    // NOTE: `pub` has to be real base64 of the right length — `PackageKey`
    // derives its kid by base64-decoding it — but the bytes need not be a
    // usable key, since the atServer treats metadata as opaque and what these
    // arms assert is the identity check in front of it.
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
                enrollmentId: other.enrollmentId, metadata: amendment()),
            lookupOf(mine)),
        throwsA(isA<Object>()),
        reason: 'holding one enrollment grants nothing over another, and a '
            'key package is an encapsulation target — being able to rewrite '
            "someone else's would let an attacker redirect their secrets");

    // Arm 2: a connection carrying no enrollment id at all — the owner's own,
    // authenticated over legacy PKAM. NOTE: isAuthorized short-circuits such a
    // connection to TRUE, so a check written as an authorization lookup rather
    // than an identity test passes here.
    await expectLater(
        AtEnrollment.create().update(
            EnrollmentUpdateRequest(
                enrollmentId: mine.enrollmentId, metadata: amendment()),
            approver.getRemoteSecondary()!.atLookUp),
        throwsA(isA<Object>()),
        reason: 'an owner connection names no enrollment, so it cannot BE the '
            'enrollment this record belongs to — despite carrying full '
            'permissions everywhere else');

    // The control: the same shape of request on its OWN connection is
    // accepted. Without it the two refusals would prove only that the verb
    // refuses everything.
    final ok = await AtEnrollment.create().update(
        EnrollmentUpdateRequest(
            enrollmentId: mine.enrollmentId, metadata: amendment()),
        lookupOf(mine));
    expect(ok.enrollmentId, mine.enrollmentId);
  });

  test('UC-A2.5 · setting keyPackage leaves a sibling metadata key alone',
      () async {
    // The per-key merge, UC-A2.5's second "Then". A whole-map replace would be
    // read-mutate-write against shared durable state: a client that has never
    // heard of a field a later build added would clobber it, and nothing would
    // report that it had.
    //
    // Driven by two enroll:updates rather than through KeyPackageMinting,
    // because what this asserts is the atSERVER's merge — the client half
    // sends one named key either way, so a client-side test could not tell a
    // merge from a replace.
    final client = await enrol('a25-merge', const [SecretSharingAlgos.xWing]);
    await (client.client as AtClientImpl).pqBootstrap!.startupComplete;

    // A field this build has no opinion about, standing in for one a later
    // build adds.
    await AtEnrollment.create().update(
        EnrollmentUpdateRequest(
            enrollmentId: client.enrollmentId,
            metadata: {'somethingLaterBuildsAdded': 'keep me'}),
        lookupOf(client));

    final pub = base64Encode(List<int>.filled(1216, 11));
    await AtEnrollment.create().update(
        EnrollmentUpdateRequest(enrollmentId: client.enrollmentId, metadata: {
          'keyPackage': KeyPackage.payloadFor(
            createdAt: DateTime.now().toUtc(),
            keys: [
              PackageKey(
                  use: SecretSharingAlgos.useEnc,
                  alg: SecretSharingAlgos.xWing,
                  pub: pub)
            ],
          )
        }),
        lookupOf(client));

    final raw = await lookupOf(client)
        .executeCommand('enroll:listns:$namespace\n', auth: true);
    final decoded =
        jsonDecode(raw!.replaceFirst(RegExp(r'^data:'), '')) as List;
    final mine = decoded
        .cast<Map<String, dynamic>>()
        .firstWhere((e) => e['enrollmentId'] == client.enrollmentId);
    final metadata = (mine['metadata'] as Map).cast<String, dynamic>();

    expect(metadata['somethingLaterBuildsAdded'], 'keep me',
        reason: 'a write naming keyPackage must not withdraw a sibling key it '
            'says nothing about — the atServer merges metadata per named key');
    expect(metadata['keyPackage'], isNotNull,
        reason: 'and the key it DID name must have landed, or this row would '
            'pass for a write that did nothing at all');
  });

  /// Re-opens [enrollmentId] as a fresh client whose preference advertises
  /// [algorithms], which is how an existing enrollment amends its package: the
  /// amendment is a startup reconciliation against the configured list, not a
  /// call.
  ///
  /// NOTE: the client cache is evicted first. `AtClientImpl` keys it by
  /// `(atSign, enrollmentId)` and `refuseChangedRolloutAxes` throws when a
  /// second client asks for the same key under different rollout axes, so
  /// without the eviction this hands back the first client.
  Future<AtClient> reopen(
      String device, String enrollmentId, List<String> algorithms) async {
    AtClientImpl.atClientInstanceMap
        .remove(AtClientImpl.instanceKey(atSign, enrollmentId));
    final keysIo = keyfiles[device]!;
    final auth = AtAuth.create();
    final response = await auth.authenticate(AtAuthRequest(
      atSign,
      rootDomain: AtRootDomain(rootDomain, TestUtils.rootServerPort),
      atKeysIo: keysIo,
    ));
    expect(response.session?.enrollmentId, enrollmentId,
        reason: 'the device keyfile must resolve to $enrollmentId, or the '
            'amendment below would be measuring the wrong enrollment');
    expect(response.isSuccessful, isTrue,
        reason: 'could not re-authenticate as $enrollmentId, so the amendment '
            'below would be measuring the wrong enrollment');

    final storage = 'test/hive/amend/$runId-$device';
    final preference = TestUtils.getPreference(atSign,
        keyEstablishmentAlgorithms: algorithms, posture: legacyPlusPqProviders)
      ..hiveStoragePath = storage
      ..commitLogPath = storage;
    final manager = await AtClientManager(atSign).setCurrentAtSign(
        atSign, namespace, preference,
        atKeysIo: keysIo,
        enrollmentId: enrollmentId,
        storage: TestUtils.storageForPrincipal(atSign, enrollmentId));
    // NOTE: startup is deliberately NOT awaited here. The PQ bootstrap sweeps
    // for envelopes, and a sweep consumes and DELETES what it opens, so a
    // caller that awaits `startupComplete` before subscribing to
    // `receivedEnvelopes` has already missed the event — that stream is a
    // broadcast stream and does not replay.
    return manager.atClient;
  }

  test('UC-A2.5 · an envelope sealed before the amendment still opens after it',
      () async {
    final recipient =
        await enrol('a25-carry', const [SecretSharingAlgos.xWing]);
    await (recipient.client as AtClientImpl).pqBootstrap!.startupComplete;

    final before = await servedPackage(recipient);
    expect(before.keys, hasLength(1),
        reason: 'the premise: this enrollment starts advertising one key, so '
            'the amendment below has something to change');
    final kpidOld = before.keys.single.kid;
    expect(kpidOld, recipient.kpid);

    // NOTE: silence the pre-amendment client first. Both it and the
    // post-amendment client sweep the same address, a sweep consumes and
    // deletes, and whichever wins is a race — so without this the envelope is
    // sometimes opened by the client that existed BEFORE the amendment, which
    // is not what this row claims.
    AtClientSecretSharing.forClient(recipient.client).stopListening();

    // Sealed to the package as it stands NOW, and deliberately left unread.
    final sender = AtClientSecretSharing(approver)
      ..sendWakeUpNotification = false;
    await sender.register();
    await sender.sendEnvelope(before, namespace, {'sealed': 'before'});

    final atRest = await recipient.client.getAtKeys(
        regex: '.*\\.$kpidOld\\.__ssenv\\..*', useRemoteAtServer: true);
    expect(atRest, isNotEmpty,
        reason: 'the envelope must be on the atServer before the amendment, '
            'or what follows proves nothing about carrying it across one');

    // WHEN the enrollment amends its package to gain a second KEM.
    final amendedClient =
        await reopen('a25-carry', recipient.enrollmentId, const [
      SecretSharingAlgos.xWing,
      SecretSharingAlgos.mlKem1024,
    ]);

    // Listener BEFORE the startup that sweeps. `forClient` returns the same
    // instance the bootstrap holds, so this is the stream the sweep emits on.
    final receiving = AtClientSecretSharing.forClient(amendedClient);
    final received = <ReceivedEnvelope>[];
    final sub = receiving.receivedEnvelopes.listen(received.add);
    addTearDown(sub.cancel);

    await (amendedClient as AtClientImpl).pqBootstrap!.startupComplete;

    final after = await servedPackage(recipient);
    expect(after.keys.map((k) => k.alg).toSet(),
        {SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024},
        reason: 'the amendment did not take, so the read below would carry '
            'the envelope across nothing');
    expect(after.keys.firstWhere((k) => k.kid == kpidOld).status,
        KeyEntryStatus.active,
        reason: 'this amendment JOINS a key rather than superseding one, so '
            'the original address stays active. A build that retired it here '
            'is exactly the defect this row names');

    // A second sweep in case the startup's own ran before the envelope was
    // visible to it; both feed the same stream, so the assertion below is on
    // what actually arrived rather than on which sweep delivered it.
    if (received.isEmpty) await receiving.sweepOnce(fromRemote: true);

    // NOTE: `anyElement(equals(...))`, not `contains(...)` — Dart Maps do not
    // override ==, so `contains` on an iterable of Maps compares identity and
    // fails against a map that is deeply equal.
    expect(received.map((e) => e.payload),
        anyElement(equals({'sealed': 'before'})),
        reason: 'the envelope sealed to $kpidOld BEFORE the amendment did not '
            'open afterwards — a secret that was correctly sent is lost, and '
            'nothing on either side would report it. A failed open does not '
            'delete the envelope (the sweep releases its claim so a later one '
            'can retry), so an empty stream here is a real failure to '
            'decrypt rather than a race with another consumer');
  }, timeout: Timeout(Duration(minutes: 4)));

  test(
      'UC-A2.5 · a sender picks by its own order and stamps the matching '
      'version', () async {
    // A differential over one recipient: the only thing that varies between
    // the two arms is the SENDER's sealsToKeyAlgorithms order. Same package,
    // same namespace, same build — so a difference in what lands can only be
    // the order.
    //
    // NOTE: the axis is `sealsToKeyAlgorithms`, not
    // `keyEstablishmentAlgorithms`. The latter is what an atSign MINTS;
    // varying it here would change the senders' own packages and nothing about
    // their choice among the recipient's.
    final recipient = await enrol('a25-negotiate', const [
      SecretSharingAlgos.xWing,
      SecretSharingAlgos.mlKem1024,
    ]);
    await (recipient.client as AtClientImpl).pqBootstrap!.startupComplete;

    final offered = await servedPackage(recipient);
    expect(offered.keys.map((k) => k.alg).toSet(),
        {SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024},
        reason: 'the premise: a recipient offering ONE key gives a sender no '
            'choice, and both arms below would agree for that reason alone');

    // NOTE: stop the recipient watching, or there is nothing to read. An
    // enrolled client sweeps for envelopes addressed to it on a timer and on
    // every sync, and a sweep CONSUMES and deletes what it opens, so each
    // arm's envelope would be gone from the atServer within moments of being
    // written. What is under test here is what the SENDER stamped.
    AtClientSecretSharing.forClient(recipient.client).stopListening();

    /// What lands at the recipient's address when [order] is the sender's
    /// preference, as ({suite, version}) read back off the atServer.
    Future<({String suite, int version})> sealedBy(
        String device, List<String> order) async {
      final client = await enrol(device, const [SecretSharingAlgos.xWing]);
      await (client.client as AtClientImpl).pqBootstrap!.startupComplete;
      // A second client for this enrollment, differing only in the sender
      // order. Evicted first, as any second construction must be.
      AtClientImpl.atClientInstanceMap
          .remove(AtClientImpl.instanceKey(atSign, client.enrollmentId));
      final storage = 'test/hive/amend/$runId-$device-sender';
      final preference = TestUtils.getPreference(atSign,
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
          sealsToKeyAlgorithms: order,
          posture: legacyPlusPqProviders)
        ..hiveStoragePath = storage
        ..commitLogPath = storage;
      final auth = AtAuth.create();
      final response = await auth.authenticate(AtAuthRequest(
        atSign,
        rootDomain: AtRootDomain(rootDomain, TestUtils.rootServerPort),
        atKeysIo: keyfiles[device]!,
      ));
      expect(response.isSuccessful, isTrue);
      expect(response.session!.enrollmentId, client.enrollmentId);
      final manager = await AtClientManager(atSign).setCurrentAtSign(
          atSign, namespace, preference,
          atKeysIo: keyfiles[device]!,
          enrollmentId: client.enrollmentId,
          storage: TestUtils.storageForPrincipal(atSign, client.enrollmentId));

      final party = AtClientSecretSharing(manager.atClient)
        ..sendWakeUpNotification = false;
      await party.register();

      // NOTE: the snapshot is taken around the SEND alone, not around the arm.
      // Enrolling and registering above both write `__ssenv` envelopes of
      // their own — approving an enrollment seals this atSign's secrets to the
      // package it advertised — so a window that opens before them attributes
      // those to this sender.
      final before = <String>{
        for (final k in await approver.getAtKeys(
            regex: '.*__ssenv.*', useRemoteAtServer: true))
          k.toString()
      };
      await party.sendEnvelope(offered, namespace, {'from': device});

      // NOTE: the arm cannot be identified by its payload, because the payload
      // is SEALED — only `suite` and the version byte are cleartext on the
      // envelope. So the new envelope is found by DIFFERENCE against what was
      // there before this arm sent, swept across EVERY __ssenv address rather
      // than `offered.kpid`: an envelope is addressed to the kid of the key
      // the sender CHOSE, so the ML-KEM arm lands somewhere the x-wing address
      // never sees.
      final now = await approver.getAtKeys(
          regex: '.*__ssenv.*', useRemoteAtServer: true);
      final fresh = now.where((k) => !before.contains(k.toString())).toList();
      expect(fresh, hasLength(1),
          reason: 'this arm must have written exactly one new envelope; '
              '${fresh.length} appeared, so the suite read below would not be '
              'attributable to this sender. Envelope keys seen: '
              '${now.map((k) => k.key).toList()}');
      final v = await approver.get(fresh.single,
          getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
      final payload =
          (SignedEnvelope.fromJson(jsonDecode(v.value as String) as Map).payload
                  as Map)
              .cast<String, dynamic>();
      return (
        suite: payload['suite'] as String,
        version: base64Decode(payload['sealed'] as String).first,
      );
    }

    final prefersXWing = await sealedBy('a25-sender-x',
        const [SecretSharingAlgos.xWing, SecretSharingAlgos.mlKem1024]);
    final prefersMlKem = await sealedBy('a25-sender-m',
        const [SecretSharingAlgos.mlKem1024, SecretSharingAlgos.xWing]);

    expect(prefersXWing.suite, SecretSharingAlgos.xWingRfc9180);
    expect(prefersMlKem.suite, SecretSharingAlgos.mlKem1024Rfc9180,
        reason: 'the recipient offers both, so a sender listing ML-KEM first '
            'must seal to the ML-KEM key. Both arms agreeing would mean the '
            "sender's order is not consulted at all");

    // And the stamped version matches the suite each arm negotiated. A
    // mismatch here opens on the far side as an AEAD failure naming neither
    // party, which is why the byte is asserted rather than the suite alone.
    //
    // NOTE: raw literals, deliberately. The version byte names the whole suite
    // on the wire and is frozen: 0x02 is RFC 9180 over X-Wing, 0x03 is RFC
    // 9180 over ML-KEM-1024. Asserting them against `sealVersionFor` would
    // compare the byte on the wire against the very function that put it
    // there, so swapping the two cases in that switch would move both sides
    // together and leave the assertions green while every peer built against
    // the published numbering fails to open what this client sends. Changing
    // either number is a wire break, and editing these two is what a reviewer
    // of that change reads.
    expect(prefersXWing.version, 0x02,
        reason: 'a peer sealing to an X-Wing key stamps pqSeal version 0x02. '
            'This is a raw literal because the wire numbering is frozen: '
            'asserting it against sealVersionFor() would compare the byte '
            'with the function that generated it and pin nothing');
    expect(prefersMlKem.version, 0x03,
        reason: 'a peer sealing to an ML-KEM-1024 key stamps pqSeal version '
            '0x03 — same reason as above, and the arm UC-A2.4 states');
    expect(prefersXWing.version, isNot(prefersMlKem.version),
        reason: 'if both stamped the same byte the version assertion above '
            'would pass for a build that ignores the negotiation entirely');
  }, timeout: Timeout(Duration(minutes: 5)));

  test('UC-A2.6 · a revoked enrollment cannot re-advertise a key package',
      () async {
    // The state gate holds without a revocation check inside enroll:update.
    // Two mechanisms close it between them, and both are asserted because
    // either alone would leave a door:
    //
    //   - the revoked enrollment can no longer authenticate at all, so the
    //     only connection that could pass the self-only check is gone; and
    //   - every other connection, the owner's included, is refused as not
    //     being that enrollment.
    final victim = await enrol('a26-revoked', const [SecretSharingAlgos.xWing]);
    await (victim.client as AtClientImpl).pqBootstrap!.startupComplete;

    Map<String, dynamic> amendment(String marker) => {
          'keyPackage': KeyPackage.payloadFor(
            createdAt: DateTime.now().toUtc(),
            keys: [
              PackageKey(
                  use: SecretSharingAlgos.useEnc,
                  alg: SecretSharingAlgos.xWing,
                  pub: base64Encode(
                      List<int>.filled(1216, marker.codeUnitAt(0))))
            ],
          )
        };

    // The control, and it runs FIRST: the same request on the same connection
    // is accepted while the enrollment is approved. Without it, the refusal
    // below is equally explained by a malformed request or a broken fixture.
    final accepted = await AtEnrollment.create().update(
        EnrollmentUpdateRequest(
            enrollmentId: victim.enrollmentId, metadata: amendment('a')),
        lookupOf(victim));
    expect(accepted.enrollmentId, victim.enrollmentId,
        reason: 'the control arm did not take, so this test cannot tell a '
            'state gate from a request the atServer never liked');

    final revoked = await approver.enrollmentService!
        .revoke(EnrollmentRequestDecision.revoked(victim.enrollmentId, atSign));
    expect(revoked.enrollmentStatus, EnrollmentStatus.revoked,
        reason: 'the atServer ACKed the revoke without moving the record, so '
            'a refusal below would not be about revocation');

    // Arm 1: the enrollment itself. It is refused before the request is even
    // considered — the connection cannot re-authenticate.
    await expectLater(
        AtEnrollment.create().update(
            EnrollmentUpdateRequest(
                enrollmentId: victim.enrollmentId, metadata: amendment('b')),
            lookupOf(victim)),
        throwsA(predicate(
            (e) => '$e'.contains('AT0027') && '$e'.contains('is revoked'))),
        reason: 'a revoked enrollment must not be able to re-advertise an '
            'encapsulation target. The assertion names AT0027 rather than '
            'accepting any throw, because a connection that failed for an '
            'unrelated reason would satisfy a bare throwsA and prove nothing');

    // Arm 2: the owner, naming it. Refused as not-self, which closes the door
    // the first arm leaves open: an owner connection is not revoked and could
    // otherwise write the record on its behalf.
    await expectLater(
        AtEnrollment.create().update(
            EnrollmentUpdateRequest(
                enrollmentId: victim.enrollmentId, metadata: amendment('c')),
            approver.getRemoteSecondary()!.atLookUp),
        throwsA(predicate((e) => '$e'.contains('self-only'))),
        reason: 'the owner connection is fully privileged and is not revoked, '
            'so if the self-only check were an authorization lookup this arm '
            'would succeed and the revoked record would be re-advertised by '
            'proxy');
  }, timeout: Timeout(Duration(minutes: 4)));
}
