import 'dart:convert';

import 'package:at_auth/at_auth.dart'
    show
        AtEnrollment,
        AtEnrollmentResponse,
        AtKeys,
        EnrollmentUpdateRequest,
        InMemoryAtKeysIo,
        KeyAlgorithmType,
        KeyEntryStatus;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/signing_key_minting.dart'
    show SigningKeyMinting;
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
    return keys.signingKeysFor(enrollmentId).map((k) => k.algorithm.name)
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
        inUseSigningAlgorithms: const {SigningAlgoType.mldsa65}));

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

  group('what it does not do', () {
    test('an empty in-use set mints nothing — the 3.x default', () async {
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference());

      expect(await minter().mintMissing(), isEmpty);
      expect(updates, isEmpty);
      expect(await heldKeyIds(), isEmpty);
    });

    test('a client with no key source mints nothing', () async {
      // A minted key that cannot be filed is one this client signs with until
      // it restarts and never again, having already published it. The
      // source-less client is a deliberate, tested property elsewhere.
      when(() => atClient.atKeysIo).thenReturn(null);

      expect(await minter().mintMissing(), isEmpty);
      expect(updates, isEmpty);
    });

    test('an algorithm already held is not minted again', () async {
      await keysIo.update(atSign.toAtsign(), (keys) {
        keys.fileSigningMaterial(
            enrollmentId: enrollmentId,
            algorithm: KeyAlgorithmType.mlDsa65,
            publicKey: base64Encode(utf8.encode('held-pub')),
            privateKey: base64Encode(utf8.encode('held-priv')));
        return true;
      });

      expect(await minter().mintMissing(), isEmpty);
      expect(updates, isEmpty,
          reason: 'nothing to advertise means nothing to publish — a start '
              'that republished every time would rewrite the record to say '
              'what it already says');
    });

    test('a second run mints nothing', () async {
      expect(await minter().mintMissing(), [SigningAlgoType.mldsa65]);
      expect(await minter().mintMissing(), isEmpty);
      expect(updates, hasLength(1));
    });
  });

  group('minting', () {
    test('mints, advertises and files the algorithm the set names', () async {
      expect(await minter().mintMissing(), [SigningAlgoType.mldsa65]);

      expect(await heldKeyIds(), ['mldsa65']);
      final keys = (await keysIo.read(atSign)).signingKeysFor(enrollmentId);
      expect(keys.single.publicKey, isNotEmpty);
      expect(keys.single.privateKey, isNotEmpty);
    });

    test('publishes BEFORE filing', () async {
      await minter().mintMissing();

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
      await minter().mintMissing();

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
      await minter().mintMissing();

      final request = updates.single;
      expect(request.enrollmentId, enrollmentId);
      expect(request.apkamPublicKey, isNull,
          reason: 'a signing key needs no server approval and no change to '
              'what authenticates — that is what makes minting unilateral');
      expect(request.metadata, isNull);
      expect(request.apskLegacy, isNull);
    });

    test('several algorithms are advertised strongest first', () async {
      when(() => atClient.getPreferences()).thenReturn(AtClientPreference(
          inUseSigningAlgorithms: const {
            SigningAlgoType.rsa2048,
            SigningAlgoType.mldsa65
          }));

      expect(await minter().mintMissing(),
          [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048]);
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
      // There is no enrollment record for the atServer to compose an _apsk
      // from, so the client is the only writer this record can have.
      expect(await minter().mintMissing(), [SigningAlgoType.mldsa65]);

      expect(updates, isEmpty);
      expect(published, hasLength(1));

      final advertised = (jsonDecode(published.single)['keys'] as List)
          .cast<Map>();
      expect(advertised.map((e) => e['alg']).toList(), ['mldsa65']);
      expect(advertised.single['status'], isNull,
          reason: 'active, which the wire spells by omitting the field');
      expect(advertised.single['pub'], isNot(pkamPublicKey()));
    });

    test('and files under the same id the reader looks for', () async {
      await minter().mintMissing();

      final keys = await keysIo.read(atSign);
      expect(keys.signingKeysFor('primary'), hasLength(1),
          reason: 'a client with no enrollment reads and writes under '
              '"primary" — two spellings would file material its own reader '
              'skips');
    });
  });

  group('what a caller sees when publishing fails', () {
    test('the key is not filed, so the next start mints a fresh one', () async {
      when(() => enrollment.update(any(), any()))
          .thenThrow(StateError('the atServer refused'));

      await expectLater(minter().mintMissing(), throwsA(isA<StateError>()));
      expect(await heldKeyIds(), isEmpty,
          reason: 'nothing is filed, so the client goes on signing with the '
              'key it already advertises and the next start retries. The '
              'advertised-but-unheld key the failed attempt may have left '
              'costs a verifier one candidate that does not match');
    });
  });
}
