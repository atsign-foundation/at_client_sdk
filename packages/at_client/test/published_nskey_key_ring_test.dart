import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

/// Discovery of another atSign's advertised nskey.
///
/// Two properties are being held here. **Freshness**: a sender never sees a
/// recipient's decapsulation fail, so re-fetching the advertisement is the only
/// way it learns of a rotation — a sender still sealing to a superseded
/// generation hands a revoked enrollment a key it can still open.
/// **Authenticity**: the key a sender seals to is the one thing an attacker
/// most wants to substitute, so an advertisement is trusted only with an APKAM
/// signature that verifies against the `_apsk` its enrollment published.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  late XWingKeyPair bobKey;
  late AtChops bobChops;
  late AtClientEnvelopeSigner bobSigner;

  setUpAll(() async {
    bobKey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  /// A mock client that signs as [enrollmentId] of [atSign].
  MockAtClient signingClient(
      String atSign, String enrollmentId, AtChops atChops) {
    final atClient = MockAtClient();
    final remoteSecondary = MockRemoteSecondary();
    final atLookUp = MockAtLookupImpl();
    when(() => atClient.atChops).thenReturn(atChops);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(remoteSecondary);
    when(() => remoteSecondary.atLookUp).thenReturn(atLookUp);
    when(() => atLookUp.enrollmentId).thenReturn(enrollmentId);
    return atClient;
  }

  setUp(() {
    bobChops = AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
    bobSigner =
        AtClientEnvelopeSigner(signingClient(bob, 'enroll-bob', bobChops));
  });

  /// The advertisement bob really publishes: a signed envelope, not a bare key.
  Future<String> signedPayloadFor(XWingKeyPair pair) async =>
      bobSigner.wrapAndSignAndJsonEncode({
        'nskeyKid': nskeyKidOf(pair.publicKeyBytes),
        'publicKey': base64Encode(pair.publicKeyBytes),
      });

  String bobsApskPublicKey() =>
      bobChops.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey;

  /// Alice's client: her advertisement fetch succeeds [succeedFor] times and
  /// throws afterwards — the shape of an atServer that goes unreachable — and
  /// her `_apsk` lookup returns [apskPublicKey].
  ({MockAtClient atClient, List<int> fetches}) client({
    int succeedFor = 999,
    required String payload,
    String? apskPublicKey,
  }) {
    final fetches = <int>[];
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    when(() => atClient.atChops).thenReturn(AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair())));
    // One answer for both gets the ring drives — the advertisement itself and
    // the `_apsk` the verify checks it against — branching on the key, because
    // a mocktail named-argument matcher also matches the argument's absence.
    Future<AtValue> answer(Invocation invocation) async {
      final key = invocation.positionalArguments.first as AtKey;
      if (key.key != '__nskey') {
        return AtValue()..value = apskPublicKey ?? bobsApskPublicKey();
      }
      fetches.add(1);
      if (fetches.length > succeedFor) {
        throw SecondaryConnectException('atServer unreachable');
      }
      return AtValue()..value = payload;
    }

    when(() => atClient.get(any())).thenAnswer(answer);
    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer(answer);
    return (atClient: atClient, fetches: fetches);
  }

  group('freshness', () {
    test('a fetched advertisement is reused inside the TTL', () async {
      final c = client(payload: await signedPayloadFor(bobKey));
      final ring = PublishedNskeyKeyRing(c.atClient,
          advertisementTtl: const Duration(minutes: 15));

      await ring.currentPublic(bob, namespace);
      await ring.currentPublic(bob, namespace);

      expect(c.fetches, hasLength(1),
          reason: 'a round trip to the recipient atServer on every put would '
              'break offline writes — the TTL is the trade');
    });

    test('the advertisement is re-fetched once the TTL has passed', () async {
      final c = client(payload: await signedPayloadFor(bobKey));
      final ring = PublishedNskeyKeyRing(c.atClient,
          advertisementTtl: const Duration(milliseconds: 1));

      await ring.currentPublic(bob, namespace);
      await Future.delayed(const Duration(milliseconds: 20));
      await ring.currentPublic(bob, namespace);

      expect(c.fetches, hasLength(2),
          reason: 're-fetching is the only way a sender learns of a rotation');
    });

    test('a failed re-fetch keeps serving the known key inside the grace',
        () async {
      final c = client(succeedFor: 1, payload: await signedPayloadFor(bobKey));
      final ring = PublishedNskeyKeyRing(c.atClient,
          advertisementTtl: const Duration(milliseconds: 1),
          advertisementStaleGrace: const Duration(minutes: 15));

      final first = await ring.currentPublic(bob, namespace);
      await Future.delayed(const Duration(milliseconds: 20));
      final second = await ring.currentPublic(bob, namespace);

      expect(second?.nskeyKid, first?.nskeyKid,
          reason: 'an ordinary blip must not cost a working key');
    });

    test('a failed re-fetch stops serving the known key past the grace',
        () async {
      final c = client(succeedFor: 1, payload: await signedPayloadFor(bobKey));
      final ring = PublishedNskeyKeyRing(c.atClient,
          advertisementTtl: const Duration(milliseconds: 1),
          advertisementStaleGrace: const Duration(milliseconds: 1));

      expect(await ring.currentPublic(bob, namespace), isNotNull);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(await ring.currentPublic(bob, namespace), isNull,
          reason: 'serving a stale generation indefinitely makes the stated '
              '"TTL plus one content key" exposure unbounded — and a peer that '
              'rotated because of a revocation is the one to stop sealing to');
    });

    test('an atSign that has never published resolves to nothing', () async {
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(alice);
      when(() => atClient.get(any()))
          .thenThrow(KeyNotFoundException('no such key'));

      expect(
          await PublishedNskeyKeyRing(atClient).currentPublic(bob, namespace),
          isNull,
          reason: 'that is the cold-start case, which belongs to the provider');
    });

    test('the ring fetches its own atSign\'s advertisement when it minted none',
        () async {
      // Another of alice's enrollments, or this one after a restart, holds
      // nothing in memory while the advertisement sits on her own atServer.
      // Reporting that as cold start would be wrong twice over: the namespace
      // is published, and a client that "fixed" it by minting would rotate the
      // key out from under every peer that had already fetched it.
      final c = client(payload: await signedPayloadFor(bobKey));

      final own = await PublishedNskeyKeyRing(c.atClient)
          .currentPublic(alice, namespace);

      expect(own, isNotNull);
      expect(c.fetches, hasLength(1),
          reason: 'served by the same lookup a peer would use, signature '
              'check included — which is what makes "one verify path, '
              'same-atSign and cross-atSign" true rather than aspirational');
    });

    test('what it minted itself costs no lookup', () async {
      final c = client(payload: await signedPayloadFor(bobKey));
      final ring = PublishedNskeyKeyRing(c.atClient);
      // Stand in for mintAndPublish, which needs a remote secondary.
      ring.rememberOwn(alice, namespace, (
        nskeyKid: nskeyKidOf(bobKey.publicKeyBytes),
        publicKey: bobKey.publicKeyBytes
      ));

      expect((await ring.currentPublic(alice, namespace))?.nskeyKid,
          nskeyKidOf(bobKey.publicKeyBytes));
      expect(c.fetches, isEmpty, reason: 'the common case stays free');
    });
  });

  group('authenticity', () {
    test('a signed advertisement verifies against the published _apsk',
        () async {
      final c = client(payload: await signedPayloadFor(bobKey));

      final advertised =
          await PublishedNskeyKeyRing(c.atClient).currentPublic(bob, namespace);

      expect(advertised?.nskeyKid, nskeyKidOf(bobKey.publicKeyBytes));
      expect(advertised?.publicKey, bobKey.publicKeyBytes);
    });

    test('an advertisement signed by another atSign is rejected', () async {
      // Bob's advertisement, but the `_apsk` served for him is somebody else's
      // — which is what a substituted key looks like from the sender's side.
      final mallory = AtChopsImpl(
          AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair()));
      final c = client(
        payload: await signedPayloadFor(bobKey),
        apskPublicKey: mallory.atChopsKeys.atPkamKeyPair!.atPublicKey.publicKey,
      );

      await expectLater(
          PublishedNskeyKeyRing(c.atClient).currentPublic(bob, namespace),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('a tampered advertisement is rejected', () async {
      // The signature stays valid for the original body; only the advertised
      // key is swapped, which is the substitution that matters.
      final envelope =
          jsonDecode(await signedPayloadFor(bobKey)) as Map<String, dynamic>;
      final mallorysKey = await XWingKeyPair.generate();
      envelope['payload'] = {
        'nskeyKid': nskeyKidOf(mallorysKey.publicKeyBytes),
        'publicKey': base64Encode(mallorysKey.publicKeyBytes),
      };
      final c = client(payload: jsonEncode(envelope));

      await expectLater(
          PublishedNskeyKeyRing(c.atClient).currentPublic(bob, namespace),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('an unsigned advertisement is rejected, not accepted bare', () async {
      final c = client(
          payload: jsonEncode({
        'nskeyKid': nskeyKidOf(bobKey.publicKeyBytes),
        'publicKey': base64Encode(bobKey.publicKeyBytes),
      }));

      await expectLater(
          PublishedNskeyKeyRing(c.atClient).currentPublic(bob, namespace),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'accepting a bare key would leave the sealing target only as '
              'trustworthy as the server that served it');
    });

    test('a kid that does not name its own key is rejected', () async {
      final otherKey = await XWingKeyPair.generate();
      final c = client(
          payload: await bobSigner.wrapAndSignAndJsonEncode({
        'nskeyKid': nskeyKidOf(otherKey.publicKeyBytes),
        'publicKey': base64Encode(bobKey.publicKeyBytes),
      }));

      await expectLater(
          PublishedNskeyKeyRing(c.atClient).currentPublic(bob, namespace),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'a conveyance sealed under a kid the recipient never minted '
              'can never be opened');
    });

    test('a verification failure is not swallowed as a cold start', () async {
      // The distinction matters: cold start falls back, a failed verify must
      // not. The provider decides what to do with the throw.
      final c = client(payload: 'not json at all');

      await expectLater(
          PublishedNskeyKeyRing(c.atClient).currentPublic(bob, namespace),
          throwsA(isA<AtSigningVerificationException>()));
    });
  });
}
