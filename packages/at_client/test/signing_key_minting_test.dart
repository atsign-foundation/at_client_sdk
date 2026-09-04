import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show
        AtEnrollment,
        AtEnrollmentResponse,
        AtKeys,
        CryptographicMaterialRole,
        EnrollmentUpdateRequest,
        InMemoryAtKeysIo,
        CryptographicMaterialAlgorithm,
        KeyEntryStatus,
        CryptographicMaterialStatus;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, EnvelopeType, signEnvelope, verifyEnvelope;
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show recordResolvedSigningAlgo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class MockAtClient extends Mock implements AtClient {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

/// Giving an enrollment signing keys of its own, per the in-use set.
///
/// The ordering assertion is the one that matters most here. Publishing after
/// filing would leave the client signing with a key its `_apsk` does not name,
/// and envelopes are stored durably — so every envelope written in that window
/// is permanently unverifiable, with nothing to retry it: the next start finds
/// the key already held and mints nothing.
void main() {
  const atSign = '@alice';
  const enrollmentId = 'enroll-a';

  late MockAtClient atClient;
  late MockAtEnrollment enrollment;
  late MockAtLookUp atLookUp;
  late AtChops atChops;
  late InMemoryAtKeysIo keysIo;

  /// Every `enroll:update` the minter sent, and what `_apsk` each advertised.
  late List<EnrollmentUpdateRequest> updates;

  /// The keyfile as it stood when each update was sent, so a test can tell
  /// "advertised, then filed" from "filed, then advertised".
  late List<List<String>> heldWhenPublished;

  String pkamPublicKey() =>
      atChops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;

  Future<List<String>> heldKeyIds() async {
    final keys = await keysIo.read(atSign);
    return keys
        .signingKeysFor(enrollmentId)
        .map((k) => k.algorithm.name)
        .toList();
  }

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(EnrollmentUpdateRequest(
        enrollmentId: 'fallback', metadata: const {'a': 'b'}));
    registerFallbackValue(MockAtLookUp());
  });

  setUp(() async {
    atChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys(atsign: atSign.toAtsign()));
    updates = [];
    heldWhenPublished = [];

    atClient = MockAtClient();
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.atKeysIo).thenReturn(keysIo);
    when(() => atClient.getPreferences()).thenReturn(AtClientPreference(
        dataSigningKeyAlgorithms: const {SigningAlgoType.mldsa65}));

    final remoteSecondary = MockRemoteSecondary();
    atLookUp = MockAtLookUp();
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);

    enrollment = MockAtEnrollment();
    when(() => enrollment.update(any(), any())).thenAnswer((i) async {
      updates.add(i.positionalArguments[0] as EnrollmentUpdateRequest);
      heldWhenPublished.add(await heldKeyIds());
      return AtEnrollmentResponse(enrollmentId, EnrollmentStatus.approved);
    });
  });

  SigningKeyMinting minter() =>
      SigningKeyMinting(atClient, enrollment: enrollment);

  /// Makes this client a **retrofitted** enrollment: its authentication key is
  /// ML-DSA-65, so the authentication and data signing keys are two different
  /// keys and the enrollment genuinely lacks any rsa2048 signing key until one
  /// is minted.
  ///
  /// Without this the fixture is a **legacy** enrollment — an rsa2048 APKAM
  /// and no typed signing material — where the one keypair does both jobs, so
  /// the enrollment already holds the rsa2048 signing key the in-use set names
  /// and the mint is correctly a no-op.
  void asRetrofittedEnrollment() =>
      recordResolvedSigningAlgo(atClient, SigningAlgoType.mldsa65);

  /// One reconciliation, returning what it minted and asserting it retired
  /// nothing.
  ///
  /// Every row below this line is about the minting half, so the retirement
  /// assertion belongs in all of them rather than in none: a change that
  /// withdrew a key on an ordinary start would otherwise pass every one.
  Future<List<SigningAlgoType>> mint() async {
    final reconciled = await minter().reconcileSigningKeys();
    expect(reconciled.retired, isEmpty,
        reason: 'nothing left the in-use set in this row, so nothing may be '
            'withdrawn — a retirement here would be one no preference asked '
            'for, and it is one-way');
    return reconciled.minted;
  }

  group('what it does not do', () {
    test('an empty in-use set mints nothing', () async {
      // The set is named rather than taken from the default. It used to be
      // the default — this test read "the 3.x default" — and the shipped
      // default is now pqReady, which keeps one classical signing key. The
      // property being pinned is the set's, not the default's, so it says so.
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference(
          posture: PqPosture.legacy, dataSigningKeyAlgorithms: const {}));

      expect(await mint(), isEmpty);
      expect(updates, isEmpty);
      expect(await heldKeyIds(), isEmpty);
    });

    test('a client with no key source mints nothing', () async {
      // A minted key that cannot be filed is one this client signs with until
      // it restarts and never again, having already published it. The
      // source-less client is a deliberate, tested property elsewhere.
      when(() => atClient.atKeysIo).thenReturn(null);

      expect(await mint(), isEmpty);
      expect(updates, isEmpty);
    });

    test('an algorithm already held is not minted again', () async {
      await keysIo.update(atSign.toAtsign(), (keys) {
        keys.fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: base64Encode(utf8.encode('held-pub')),
            privateKey: base64Encode(utf8.encode('held-priv')));
        return true;
      });

      expect(await mint(), isEmpty);
      expect(updates, isEmpty,
          reason: 'nothing to advertise means nothing to publish — a start '
              'that republished every time would rewrite the record to say '
              'what it already says');
    });

    test('a second run mints nothing', () async {
      expect(await mint(), [SigningAlgoType.mldsa65]);
      expect(await mint(), isEmpty);
      expect(updates, hasLength(1));
    });
  });

  group('minting', () {
    test('mints, advertises and files the algorithm the set names', () async {
      expect(await mint(), [SigningAlgoType.mldsa65]);

      expect(await heldKeyIds(), ['mldsa65']);
      final keys = (await keysIo.read(atSign)).signingKeysFor(enrollmentId);
      expect(keys.single.publicKey, isNotEmpty);
      expect(keys.single.privateKey, isNotEmpty);
    });

    test('publishes BEFORE filing', () async {
      await mint();

      expect(heldWhenPublished, [<String>[]],
          reason: 'the keyfile held no signing key at the moment the '
              'advertisement went out. Filing first would have the client '
              'signing under a key its _apsk does not name, and every envelope '
              'written before the publish landed is unverifiable for good');
      expect(await heldKeyIds(), ['mldsa65'],
          reason: 'and it is filed by the time the call returns');
    });

    test('the advertisement names the minted key and drops the auth key',
        () async {
      await mint();

      final advertised = updates.single.signingKeys!;
      expect(advertised.map((e) => e.alg).toList(), [SigningAlgoType.mldsa65]);
      expect(advertised.single.status, KeyEntryStatus.active);
      expect(advertised.single.pub, isNot(pkamPublicKey()),
          reason: 'the APKAM authentication key stops being advertised the '
              'moment this enrollment holds a signing key of its own. It is '
              'not retained: a key is kept for what it SIGNED, and an '
              'enrollment holding signing keys signs nothing with its auth '
              'key that outlives the transition');
    });

    test('the update names this enrollment and changes nothing else', () async {
      await mint();

      final request = updates.single;
      expect(request.enrollmentId, enrollmentId);
      expect(request.apkamPublicKey, isNull,
          reason: 'a signing key needs no server approval and no change to '
              'what authenticates — that is what makes minting unilateral');
      expect(request.metadata, isNull);
      expect(request.apskLegacy, isNull);
    });

    test('a single rsa2048 key is advertised in the bare form', () async {
      // A retrofitted enrollment minting the rsa2048 signing key its stage
      // names. Every deployed `_apsk` consumer base64-decodes the value as an
      // RSA key, so a one-entry JSON array here is fail-closed but
      // service-breaking for anything already running — the breakage rollout 1
      // exists to prevent, arriving from the heal path instead of the request
      // path.
      asRetrofittedEnrollment();
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference(
          dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048}));

      expect(await mint(), [SigningAlgoType.rsa2048]);

      final request = updates.single;
      expect(request.signingKeys, isNull,
          reason: 'the two are mutually exclusive: one enrollment publishes '
              'one _apsk value, and the atServer refuses a request carrying '
              'both');
      expect(
          request.apskLegacy,
          (await keysIo.read(atSign))
              .signingKeysFor(enrollmentId)
              .single
              .publicKey,
          reason: 'the bare form IS the key, and it is the key this client '
              'just filed — not the APKAM authentication key it used to be');
    });

    test('several algorithms are advertised strongest first', () async {
      asRetrofittedEnrollment();
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference(
          dataSigningKeyAlgorithms: const {
            SigningAlgoType.rsa2048,
            SigningAlgoType.mldsa65
          }));

      expect(await mint(), [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048]);
      expect(updates.single.signingKeys!.map((e) => e.alg).toList(),
          [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048],
          reason: 'the two minted keys and nothing else — the APKAM '
              'authentication key is rsa2048 too, and a third entry here '
              'would be it');
      expect(await heldKeyIds(), ['mldsa65', 'rsa2048']);
    });
  });

  group('a client with no enrollment', () {
    late List<String> published;

    setUp(() {
      when(() => atLookUp.enrollmentId).thenReturn(null);
      published = [];
      when(() => atClient.get(any(),
              getRequestOptions: any(named: 'getRequestOptions')))
          .thenAnswer((_) => throw AtKeyNotFoundException('not there'));
      when(() => atClient.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((i) {
        published.add(i.positionalArguments[1] as String);
        return Future.value(true);
      });
    });

    test('publishes the record itself rather than sending enroll:update',
        () async {
      // The client can name no enrollment, so it can send no enroll:update
      // for the atServer to compose an _apsk from — which makes the client the
      // only writer this record can have.
      expect(await mint(), [SigningAlgoType.mldsa65]);

      expect(updates, isEmpty);
      expect(published, hasLength(1));

      final advertised =
          (jsonDecode(published.single)['keys'] as List).cast<Map>();
      expect(advertised.map((e) => e['alg']).toList(), ['mldsa65']);
      expect(advertised.single['status'], isNull,
          reason: 'active, which the wire spells by omitting the field');
      expect(advertised.single['pub'], isNot(pkamPublicKey()));
    });

    test('and files under the same id the reader looks for', () async {
      await mint();

      final keys = await keysIo.read(atSign);
      expect(keys.signingKeysFor('primary'), hasLength(1),
          reason: 'a client with no enrollment reads and writes under '
              '"primary" — two spellings would file material its own reader '
              'skips');
    });
  });

  /// A stage transition — the one thing no rail in this project covers.
  ///
  /// The rollout matrix copies a **fresh keyfile per cell**, so it never moves
  /// one client from one stage to the next; every cell measures a client born
  /// at its stage. The move from an in-use set of `{rsa2048}` to `{mldsa65}`
  /// is where a signing key is actually withdrawn, and until this group
  /// existed nothing exercised it at any layer.
  ///
  /// What must hold across the move: the old key stops signing, stays
  /// advertised as `retired`, and what it signed still verifies. The last of
  /// those is the point of retaining it at all, and it is asserted here
  /// against real published values rather than a reconstruction of them.
  group('a stage transition', () {
    void inUse(Set<SigningAlgoType> algorithms) {
      when(() => atClient.getPreferences())
          .thenReturn(AtClientPreference(dataSigningKeyAlgorithms: algorithms));
    }

    Future<AtKeys> keyfile() async => keysIo.read(atSign);

    /// The rollout-1 starting position: this enrollment holds an RSA-2048
    /// signing key of its own and advertises it.
    Future<void> atRollout1() async {
      // A retrofitted enrollment, which is what this group is about: the move
      // from {rsa2048} to {mldsa65} is a transition an enrollment makes after
      // its authentication key has already gone post-quantum.
      asRetrofittedEnrollment();
      inUse({SigningAlgoType.rsa2048});
      expect((await minter().reconcileSigningKeys()).minted,
          [SigningAlgoType.rsa2048]);
    }

    test('retires the superseded key and mints its replacement', () async {
      await atRollout1();
      final wasSigning = (await keyfile()).signingKeysFor(enrollmentId).single;

      inUse({SigningAlgoType.mldsa65});
      final reconciled = await minter().reconcileSigningKeys();

      expect(reconciled.minted, [SigningAlgoType.mldsa65]);
      expect(reconciled.retired, [SigningAlgoType.rsa2048]);
      expect(await heldKeyIds(), ['mldsa65'],
          reason: 'the withdrawn key is no longer one this client signs with, '
              'so an envelope written after the move carries one signature '
              'rather than two');

      final keys = await keyfile();
      final retired = keys.withdrawnSigningKeysFor(enrollmentId).single;
      expect(retired.algorithm, SigningAlgoType.rsa2048);
      expect(retired.publicKey, wasSigning.publicKey,
          reason: 'the same key, moved rather than replaced — a fresh RSA key '
              'here would verify nothing that was signed before the move');

      for (final part in [
        CryptographicMaterialRole.privateSigning,
        CryptographicMaterialRole.publicVerification
      ]) {
        final material = keys.getKey(enrollmentId, 'sign:rsa2048:1', part);
        expect(material?.status, CryptographicMaterialStatus.retired,
            reason: 'both halves move: a keypair half-retired at rest is one '
                'the next reader can read either way');
        expect(material?.bytes.toString(), isNotEmpty,
            reason: 'retired, not removed — nothing in a keyfile is deleted');
      }
    });

    test('advertises the retired key beside the new one', () async {
      await atRollout1();

      inUse({SigningAlgoType.mldsa65});
      await minter().reconcileSigningKeys();

      final advertised = updates.last.signingKeys!;
      expect(advertised.map((e) => e.alg).toList(),
          [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048],
          reason: 'strongest first, the active one leading');
      expect(advertised.first.status, KeyEntryStatus.active);
      expect(advertised.last.status, KeyEntryStatus.retired);
      expect(
          advertised.last.pub,
          (await keyfile())
              .withdrawnSigningKeysFor(enrollmentId)
              .single
              .publicKey,
          reason:
              'the advertisement and the keyfile name one key. A withdrawal '
              'that dropped the entry instead of retiring it would unverify '
              'every envelope it signed, and the key package it signed with it');
    });

    test('advertises the withdrawal before filing it', () async {
      await atRollout1();

      inUse({SigningAlgoType.mldsa65});
      await minter().reconcileSigningKeys();

      expect(heldWhenPublished.last, ['rsa2048'],
          reason: 'the keyfile still held the outgoing key as active when the '
              'advertisement went out, and the new one was not filed yet. The '
              'other order leaves a moment with no active signing key, where '
              'the client falls back to signing with its APKAM authentication '
              'key — which this advertisement has already stopped naming');
    });

    test('retires even when there is nothing left to mint', () async {
      // The state a client reaches by crashing between the two writes, or by
      // upgrading to a build that retires. Returning early on an empty
      // *missing* set — which is what this used to do — leaves the stale key
      // active for good, because a start with nothing to mint never looks.
      await atRollout1();
      inUse({SigningAlgoType.rsa2048, SigningAlgoType.mldsa65});
      expect((await minter().reconcileSigningKeys()).minted,
          [SigningAlgoType.mldsa65]);
      final before = updates.length;

      inUse({SigningAlgoType.mldsa65});
      final reconciled = await minter().reconcileSigningKeys();

      expect(reconciled.minted, isEmpty);
      expect(reconciled.retired, [SigningAlgoType.rsa2048]);
      expect(updates, hasLength(before + 1),
          reason: 'a withdrawal is a change to the record, so it is published '
              'even though nothing was minted');
      expect(await heldKeyIds(), ['mldsa65']);
    });

    test('a start after the move changes nothing', () async {
      await atRollout1();
      inUse({SigningAlgoType.mldsa65});
      await minter().reconcileSigningKeys();
      final settled = updates.length;

      final reconciled = await minter().reconcileSigningKeys();

      expect(reconciled.minted, isEmpty);
      expect(reconciled.retired, isEmpty,
          reason: 'the key is already retired and retirement is one-way — a '
              'start that retired it again would rewrite the record on every '
              'boot and, at rollout 2, republish an unchanged array');
      expect(updates, hasLength(settled));
    });

    test('an empty in-use set withdraws nothing', () async {
      // The released posture. Every algorithm is out of the set, and this is
      // deliberately NOT read as "retire everything": a client there goes on
      // signing with the key it holds and advertising it bare, which is what
      // that posture publishes. Retiring would drop it to signing with its
      // authentication key and turn the advertisement into an array.
      await atRollout1();
      final settled = updates.length;

      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());
      final reconciled = await minter().reconcileSigningKeys();

      expect(reconciled.retired, isEmpty);
      expect(updates, hasLength(settled));
      expect(await heldKeyIds(), ['rsa2048']);
    });

    test('a re-minted algorithm is advertised beside the key it replaced',
        () async {
      await atRollout1();
      final firstGeneration =
          (await keyfile()).signingKeysFor(enrollmentId).single.publicKey;

      inUse({SigningAlgoType.mldsa65});
      await minter().reconcileSigningKeys();
      inUse({SigningAlgoType.mldsa65, SigningAlgoType.rsa2048});
      expect((await minter().reconcileSigningKeys()).minted,
          [SigningAlgoType.rsa2048]);

      final keys = await keyfile();
      expect(keys.signingKeysFor(enrollmentId).map((k) => k.algorithm).toList(),
          [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048]);
      expect(
          keys.getKey(enrollmentId, 'sign:rsa2048:2',
              CryptographicMaterialRole.publicVerification),
          isNotNull,
          reason: 'the generation is the slot: the returning algorithm lands '
              'beside its retired predecessor rather than over it');

      final advertised = updates.last.signingKeys!;
      expect(advertised, hasLength(3),
          reason: 'two active and one retired. This is the publish that '
              're-reads the retired set rather than assuming it empty — an '
              'enrollment must not lose the retained entry at the moment it '
              'gains a replacement, which is exactly when the old key\'s '
              'envelopes still need verifying');
      expect(
          advertised
              .where((e) => e.status == KeyEntryStatus.retired)
              .single
              .pub,
          firstGeneration);
    });

    /// UC-G1.9 — the reason a retired key is retained at all.
    ///
    /// Runs on the no-enrollment arm because that is the path where this
    /// client composes the `_apsk` **value**: the enrolled path hands entries
    /// to the atServer, so a test there would have to reconstruct the wire
    /// form, and a pin fed a reconstruction proves what the test can build
    /// rather than what the client published.
    test('an envelope written AFTER the withdrawal carries no signature of it',
        () async {
      // The row's first clause is "new envelopes carry no signature of it".
      // Every arm asserting it read the held key SET — what this client COULD
      // sign with — which is a proxy for what a composed envelope actually
      // carries. This composes one, from what the production selector offers
      // rather than from a key picked by hand.
      await atRollout1();

      // The control, taken BEFORE the move: an envelope built the same way
      // does carry the RSA signature. Without it, "no RS256 entry" would be
      // satisfied by an envelope carrying no entries at all.
      final atRollout1Envelope = signEnvelope('written at rollout 1',
          keys: await minter().signingKeys, type: EnvelopeType.app);
      expect(
          atRollout1Envelope.signatures.map((s) => s.alg).toList(), ['RS256'],
          reason: 'the control: while rsa2048 is in use, the composed '
              'envelope is signed under it');

      inUse({SigningAlgoType.mldsa65});
      await minter().reconcileSigningKeys();

      final afterTheMove = signEnvelope('written after the move',
          keys: await minter().signingKeys, type: EnvelopeType.app);
      expect(afterTheMove.signatures.map((s) => s.alg).toList(), ['ML-DSA-65'],
          reason: 'ONE entry, under the new algorithm: the withdrawn key is '
              'no longer offered for new operations, so nothing signs with '
              'it. An envelope carrying both would leave a verifier free to '
              'accept the weaker one');
      expect(
          afterTheMove.signatures.map((s) => s.alg), isNot(contains('RS256')),
          reason: 'stated the way the row states it — no signature OF the '
              'retired algorithm — so a future build that emitted several '
              'entries would still have to leave this one out');

      // The row's other two clauses, so the three are read together: the key
      // is retired rather than dropped, which is what keeps the envelope
      // above's predecessor verifiable.
      final withdrawn =
          (await keyfile()).withdrawnSigningKeysFor(enrollmentId).single;
      expect(withdrawn.algorithm, SigningAlgoType.rsa2048,
          reason: 'retained as retired, not deleted — the keys an enrollment '
              'has withdrawn are exactly the ones its stored envelopes were '
              'signed with, so dropping the entry would strand the envelope '
              'this one signed a moment ago');
    });

    test('an envelope signed before the withdrawal still verifies', () async {
      // A retrofitted enrollment, as everywhere in this group. The null
      // enrollment id is only how this row reaches the simpler publish path
      // (a direct put rather than an `enroll:update`); the claim below is
      // about what a withdrawal does to an envelope, not about enrollment
      // identity.
      asRetrofittedEnrollment();
      when(() => atLookUp.enrollmentId).thenReturn(null);
      final published = <String>[];
      when(() => atClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
        if (published.isEmpty) throw AtKeyNotFoundException('not there');
        return Future.value(AtValue()..value = published.last);
      });
      when(() => atClient.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((i) {
        published.add(i.positionalArguments[1] as String);
        return Future.value(true);
      });

      inUse({SigningAlgoType.rsa2048});
      await minter().reconcileSigningKeys();

      final rollout1Key = (await keyfile()).signingKeysFor('primary').single;
      final envelope = signEnvelope('what rollout 1 signed',
          keys: [
            ApkamSigningKeys(
                algorithm: rollout1Key.algorithm,
                publicKey: rollout1Key.publicKey,
                privateKey: rollout1Key.privateKey)
          ],
          type: EnvelopeType.app);
      await verifyEnvelope(envelope,
          signerPublicKey: published.single, expecting: EnvelopeType.app);

      inUse({SigningAlgoType.mldsa65});
      await minter().reconcileSigningKeys();

      expect(published, hasLength(2),
          reason: 'the record moved, so it was rewritten — a client that '
              'skipped the publish would leave the withdrawn key advertised '
              'as current');
      await verifyEnvelope(envelope,
          signerPublicKey: published.last, expecting: EnvelopeType.app);
    });

    /// UC-G2.9 — the overlap a migration with a verifier gap was thought to
    /// need. ⛔ RETIRED by decisions.md 120 on 2026-08-28: an attacker strips
    /// the stronger signature and the verifier accepts the weaker, because
    /// nothing lets it insist. This test is KEPT so it goes red the day the
    /// multi-signature writer is removed.
    ///
    /// The gap this closes: a two-member `dataSigningKeyAlgorithms` is set in
    /// exactly two tests elsewhere and NEITHER reaches an envelope — one
    /// asserts mint order, the other set equality. So nothing established that
    /// the PREFERENCE, rather than hand-supplied key material, is what produces
    /// a two-signature envelope. And the direction the overlap exists for — a
    /// verifier implementing one of the two ACCEPTING such an envelope — was
    /// asserted nowhere; only the refusal was.
    test(
        'a two-member in-use set signs twice, and a one-algorithm verifier '
        'still verifies', () async {
      // A retrofitted enrollment, as everywhere in this group. The null
      // enrollment id is only how this row reaches the simpler publish path
      // (a direct put rather than an `enroll:update`); the claim below is
      // about what a withdrawal does to an envelope, not about enrollment
      // identity.
      asRetrofittedEnrollment();
      when(() => atLookUp.enrollmentId).thenReturn(null);
      final published = <String>[];
      when(() => atClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((_) {
        if (published.isEmpty) throw AtKeyNotFoundException('not there');
        return Future.value(AtValue()..value = published.last);
      });
      when(() => atClient.put(any(), any(),
          putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((i) {
        published.add(i.positionalArguments[1] as String);
        return Future.value(true);
      });

      // The control, and it has to come first: without it "two signatures"
      // would be satisfied by a build that emits every key it holds whatever
      // the set says.
      inUse({SigningAlgoType.rsa2048});
      await minter().reconcileSigningKeys();
      final one = signEnvelope('one member',
          keys: await minter().signingKeys, type: EnvelopeType.app);
      expect(one.signatures.map((s) => s.alg).toList(), ['RS256'],
          reason: 'the control: a single-member set emits exactly one '
              'signature, so the pair below is attributable to the SET rather '
              'than to this client always signing with everything it holds');
      final rsaOnlyApsk = published.last;

      inUse({SigningAlgoType.rsa2048, SigningAlgoType.mldsa65});
      await minter().reconcileSigningKeys();
      final two = signEnvelope('two members',
          keys: await minter().signingKeys, type: EnvelopeType.app);
      expect(two.signatures.map((s) => s.alg).toList(), ['ML-DSA-65', 'RS256'],
          reason: 'one signature per active signing key, strongest first — '
              'and reached through the PREFERENCE and the production selector, '
              'not from key material handed to signEnvelope by the test');

      // The direction the overlap exists for. `rsaOnlyApsk` is the record as
      // it stood before the second algorithm was minted, which is exactly what
      // a verifier that has not upgraded would have been served.
      await verifyEnvelope(two,
          signerPublicKey: rsaOnlyApsk, expecting: EnvelopeType.app);

      // And a verifier served the current record takes the STRONGEST shared
      // rather than the first entry, so the upgrade takes effect for it.
      await verifyEnvelope(two,
          signerPublicKey: published.last, expecting: EnvelopeType.app);
    });
  });

  /// A legacy enrollment's authentication keypair IS its data signing keypair
  /// — one rsa2048 key doing both jobs. `AtKeys.signingKeysFor` cannot see it,
  /// because it reads typed per-enrollment material and a legacy keyfile
  /// carries flat fields, so the mint used to conclude the enrollment held no
  /// signing key, generate a SECOND rsa2048 keypair and publish it — dropping
  /// the original from `_apsk` and leaving whatever it signed unverifiable.
  ///
  /// The whole value of the fix is its SCOPE, so the discriminating cases are
  /// here beside it.
  group('a legacy enrollment already holds its data signing key', () {
    void inUse(Set<SigningAlgoType> algorithms) {
      when(() => atClient.getPreferences())
          .thenReturn(AtClientPreference(dataSigningKeyAlgorithms: algorithms));
    }

    test('so an in-use set naming rsa2048 mints nothing', () async {
      // The fixture is legacy by construction: an rsa2048 APKAM keypair and a
      // keyfile with no typed signing material.
      inUse({SigningAlgoType.rsa2048});

      final reconciled = await minter().reconcileSigningKeys();

      expect(reconciled.minted, isEmpty,
          reason: 'the enrollment holds an rsa2048 signing key already — the '
              'one it authenticates with. A second one is the same algorithm '
              'and buys nothing');
      expect(reconciled.retired, isEmpty);
      expect(updates, isEmpty,
          reason: 'and nothing is published, so the advertisement goes on '
              'naming the key that signed what this enrollment has signed');
      expect(await heldKeyIds(), isEmpty);
    });

    test('an ML-DSA-authenticating enrollment holding none still mints one',
        () async {
      // ⛔ **The control that makes the scope mean something, and the only
      // state that discriminates the two forms.** ML-DSA authentication key,
      // no typed signing material, in-use set naming ML-DSA:
      //
      // - excluding **rsa2048** leaves mldsa65 missing, so it is minted;
      // - excluding **whatever the authentication keypair reports** empties
      //   `missing`, nothing is ever minted, and `_apsk` advertises the
      //   authentication key as its sole active entry — the auth/signing split
      //   collapsing on the posture that exists to create it, silently.
      //
      // Reachable today: an enrollment created at pqActive before the enrolment
      // path minted a signing key of its own is in exactly this state.
      asRetrofittedEnrollment();
      inUse({SigningAlgoType.mldsa65});

      expect((await minter().reconcileSigningKeys()).minted,
          [SigningAlgoType.mldsa65]);
      expect(await heldKeyIds(), ['mldsa65']);
    });

    test('and a legacy enrollment at pqActive mints ML-DSA too', () async {
      // rsa2048 authentication, ML-DSA wanted: the exclusion cannot fire,
      // because it names rsa2048 and rsa2048 is not what the set wants.
      inUse({SigningAlgoType.mldsa65});

      expect((await minter().reconcileSigningKeys()).minted,
          [SigningAlgoType.mldsa65]);
    });

    test('and a RETROFITTED enrollment still mints rsa2048', () async {
      // The other half of the scope: once the authentication key is ML-DSA the
      // two keys are genuinely different, so the enrollment really does lack
      // an rsa2048 signing key and really must mint one.
      asRetrofittedEnrollment();
      inUse({SigningAlgoType.rsa2048});

      expect((await minter().reconcileSigningKeys()).minted,
          [SigningAlgoType.rsa2048]);
      expect(await heldKeyIds(), ['rsa2048']);
    });
  });

  group('what a caller sees when publishing fails', () {
    test('the key is not filed, so the next start mints a fresh one', () async {
      when(() => enrollment.update(any(), any()))
          .thenThrow(StateError('the atServer refused'));

      await expectLater(
          minter().reconcileSigningKeys(), throwsA(isA<StateError>()));
      expect(await heldKeyIds(), isEmpty,
          reason: 'nothing is filed, so the client goes on signing with the '
              'key it already advertises and the next start retries. The '
              'advertised-but-unheld key the failed attempt may have left '
              'costs a verifier one candidate that does not match');
    });
  });
}
