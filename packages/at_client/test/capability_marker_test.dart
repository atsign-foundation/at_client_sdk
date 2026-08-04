import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

/// The capability marker — the record a fleet advertises its readable schemes
/// in, and the only evidence scheme negotiation ever acts on.
///
/// Two properties matter more than the round trip. It has to be **verifiable**:
/// a marker an attacker can write is a marker that demotes every sender to
/// legacy without touching a key. And it has to be **conservative when
/// composed**: a record in a nested namespace is read by enrollments authorised
/// at every level above it, so the schemes they *all* support is an
/// intersection, never the first hit found walking up.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
  });

  /// One shared key-value space standing in for both atServers, so a marker
  /// alice publishes is exactly the bytes bob's client fetches — including the
  /// `_apsk` his verify has to check the signature against.
  late Map<String, String> atServer;

  /// Whether the atServer answers at all. Distinct from an empty [atServer] on
  /// purpose: "the record is not there" and "I could not ask" are different
  /// answers, and the marker cache is required to treat them differently.
  late bool atServerReachable;

  /// A client of [atSign] whose puts and update verbs land in [atServer] and
  /// whose gets read from it.
  MockAtClient clientFor(String atSign, String enrollmentId) {
    final atClient = MockAtClient();
    final secondary = MockRemoteSecondary();
    final lookUp = MockAtLookup();

    when(() => atClient.atChops).thenReturn(AtChopsImpl(
        AtChopsKeys.create(null, AtChopsUtil.generateAtPkamKeyPair())));
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.getRemoteSecondary()).thenReturn(secondary);
    when(() => secondary.atLookUp).thenReturn(lookUp);
    when(() => lookUp.enrollmentId).thenReturn(enrollmentId);

    when(() => atClient.get(any(),
        getRequestOptions: any(named: 'getRequestOptions'))).thenAnswer((inv) {
      final key = (inv.positionalArguments[0] as AtKey).toString();
      if (!atServerReachable) {
        throw AtLookUpException('AT0013', 'could not reach the atServer');
      }
      final value = atServer[key];
      if (value == null) throw AtKeyNotFoundException(key);
      return Future.value(AtValue()..value = value);
    });
    when(() => atClient.put(any(), any(),
        putRequestOptions: any(named: 'putRequestOptions'))).thenAnswer((inv) {
      atServer[(inv.positionalArguments[0] as AtKey).toString()] =
          '${inv.positionalArguments[1]}';
      return Future.value(true);
    });
    when(() => secondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) {
      final builder = inv.positionalArguments[0];
      if (builder is UpdateVerbBuilder) {
        atServer[builder.atKey.toString()] = builder.value;
      }
      return Future.value('data:1');
    });
    return atClient;
  }

  setUp(() {
    atServer = {};
    atServerReachable = true;
  });

  group('publishing and reading a marker', () {
    test('a peer reads exactly what was published, signature and all',
        () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final bobClient = clientFor(bob, 'enroll-b');

      await PublishedCapabilities(aliceClient).publish(
          namespace: namespace,
          schemes: {legacyCryptoProviderId, nskeyCryptoProviderId});

      expect(
          await PublishedCapabilities(bobClient).advertisedBy(alice, namespace),
          {legacyCryptoProviderId, nskeyCryptoProviderId},
          reason: 'the whole negotiation runs on this one read');
    });

    test('a fleet that has published nothing is no evidence, not legacy-only',
        () async {
      final bobClient = clientFor(bob, 'enroll-b');

      expect(
          await PublishedCapabilities(bobClient).advertisedBy(alice, namespace),
          isNull,
          reason: 'an unreachable atServer and a fleet that never upgraded are '
              'indistinguishable here, so this must not be reported as a fleet '
              'that has told us it reads legacy only');
    });

    test('an unsigned marker is refused rather than believed', () async {
      final bobClient = clientFor(bob, 'enroll-b');
      // What an attacker who can write to the record — or an atServer operator
      // — would put there: a well-formed capability with no signature over it.
      atServer[capabilityAdvertisementKey(alice, namespace).toString()] =
          jsonEncode({
        'payload': {
          'schemes': [legacyCryptoProviderId]
        }
      });

      expect(
          await PublishedCapabilities(bobClient).advertisedBy(alice, namespace),
          isNull,
          reason: 'a marker anyone can forge is a downgrade attack that needs '
              'no key material at all, so it must not be treated as evidence');
    });

    test('a marker signed by another atSign is refused', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final malloryClient = clientFor('@mallory', 'enroll-m');
      final bobClient = clientFor(bob, 'enroll-b');

      // Mallory signs a legacy-only capability with her own APKAM keypair and
      // it is placed at alice's address. Her `_apsk` is published and valid —
      // it is simply not alice's.
      await PublishedCapabilities(malloryClient)
          .publish(namespace: namespace, schemes: {legacyCryptoProviderId});
      atServer[capabilityAdvertisementKey(alice, namespace).toString()] =
          atServer[
              capabilityAdvertisementKey('@mallory', namespace).toString()]!;

      // Control: alice's own marker verifies through the same path, so the
      // refusal below is about who signed it and not about the plumbing.
      await PublishedCapabilities(aliceClient)
          .publish(namespace: 'other', schemes: {legacyCryptoProviderId});
      expect(
          await PublishedCapabilities(bobClient).advertisedBy(alice, 'other'),
          {legacyCryptoProviderId});

      expect(
          await PublishedCapabilities(bobClient).advertisedBy(alice, namespace),
          isNull);
    });
  });

  group('composed namespaces', () {
    test('every level that carries a marker is intersected', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final bobClient = clientFor(bob, 'enroll-b');

      // The fleet authorised for the whole of `my_apps` has upgraded; the one
      // authorised only for `app_1.my_apps` has not.
      await PublishedCapabilities(aliceClient).publish(
          namespace: 'my_apps',
          schemes: {legacyCryptoProviderId, nskeyCryptoProviderId});
      await PublishedCapabilities(aliceClient)
          .publish(namespace: namespace, schemes: {legacyCryptoProviderId});

      expect(
          await PublishedCapabilities(bobClient).advertisedBy(alice, namespace),
          {legacyCryptoProviderId},
          reason: 'a record at app_1.my_apps is read by enrollments authorised '
              'at either level, so taking the first hit walking up would write '
              'a scheme the deeper, more narrowly authorised fleet cannot read');
    });

    test('a marker on an ancestor answers for a namespace with none', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final bobClient = clientFor(bob, 'enroll-b');

      await PublishedCapabilities(aliceClient).publish(
          namespace: 'my_apps',
          schemes: {legacyCryptoProviderId, nskeyCryptoProviderId});

      expect(
          await PublishedCapabilities(bobClient)
              .advertisedBy(alice, 'sub.$namespace'),
          {legacyCryptoProviderId, nskeyCryptoProviderId},
          reason: 'sub-collections compose a per-item namespace, so requiring '
              'a marker at the exact level would leave every one of them '
              'un-negotiable');
    });
  });

  group('caching', () {
    test('a second read costs no round trip', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final bobClient = clientFor(bob, 'enroll-b');
      await PublishedCapabilities(aliceClient)
          .publish(namespace: 'my_apps', schemes: {legacyCryptoProviderId});

      final capabilities = PublishedCapabilities(bobClient);
      await capabilities.advertisedBy(alice, 'my_apps');
      // Control: the first read really did go to the atServer, so the silence
      // below is a cache hit rather than a call that never happens.
      verify(() => bobClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).called(2);

      await capabilities.advertisedBy(alice, 'my_apps');

      verifyNever(() => bobClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions')));
    });

    test('a miss is cached too', () async {
      final bobClient = clientFor(bob, 'enroll-b');
      final capabilities = PublishedCapabilities(bobClient);

      await capabilities.advertisedBy(alice, 'my_apps');
      verify(() => bobClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions'))).called(1);

      await capabilities.advertisedBy(alice, 'my_apps');

      verifyNever(() => bobClient.get(any(),
          getRequestOptions: any(named: 'getRequestOptions')));
    });

    test('an expired answer is re-fetched, and a flip is then seen', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final bobClient = clientFor(bob, 'enroll-b');
      final capabilities = PublishedCapabilities(bobClient, ttl: Duration.zero);

      await PublishedCapabilities(aliceClient)
          .publish(namespace: 'my_apps', schemes: {legacyCryptoProviderId});
      expect(await capabilities.advertisedBy(alice, 'my_apps'),
          {legacyCryptoProviderId});

      await PublishedCapabilities(aliceClient).publish(
          namespace: 'my_apps',
          schemes: {legacyCryptoProviderId, nskeyCryptoProviderId});

      expect(await capabilities.advertisedBy(alice, 'my_apps'),
          {legacyCryptoProviderId, nskeyCryptoProviderId},
          reason: 'the ttl is the whole lever on how long a flip goes '
              'unnoticed');
    });

    test('a failed re-fetch keeps serving the last answer, inside the grace',
        () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final bobClient = clientFor(bob, 'enroll-b');
      final capabilities = PublishedCapabilities(bobClient,
          ttl: Duration.zero, staleGrace: const Duration(minutes: 15));

      await PublishedCapabilities(aliceClient).publish(
          namespace: 'my_apps',
          schemes: {legacyCryptoProviderId, nskeyCryptoProviderId});
      await capabilities.advertisedBy(alice, 'my_apps');

      // The atServer goes away — not the record.
      atServerReachable = false;

      expect(await capabilities.advertisedBy(alice, 'my_apps'),
          {legacyCryptoProviderId, nskeyCryptoProviderId},
          reason: 'a blip must not change what a client writes');
    });

    test('past the grace, a failed re-fetch drops the answer', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      final bobClient = clientFor(bob, 'enroll-b');
      final capabilities = PublishedCapabilities(bobClient,
          ttl: Duration.zero, staleGrace: Duration.zero);

      await PublishedCapabilities(aliceClient).publish(
          namespace: 'my_apps',
          schemes: {legacyCryptoProviderId, nskeyCryptoProviderId});
      await capabilities.advertisedBy(alice, 'my_apps');

      atServerReachable = false;

      expect(await capabilities.advertisedBy(alice, 'my_apps'), isNull,
          reason: 'held forever, a stale ready marker would keep senders '
              'writing a scheme the fleet may have just withdrawn');
    });
  });

  group('the operator flip', () {
    test('an upgraded client publishes not-ready, naming legacy alone',
        () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      aliceClient.getPreferences().crypto =
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());

      expect(
          await CryptoRollout(aliceClient).publishNotReadyIfAbsent(namespace),
          isTrue);

      expect(
          await PublishedCapabilities(clientFor(bob, 'enroll-b'))
              .advertisedBy(alice, namespace),
          {legacyCryptoProviderId},
          reason: 'this client reads the post-quantum pair, but a sibling '
              'enrollment may still be an old build — the marker states the '
              'fleet, not the publisher');
    });

    test('start-up seeding never overwrites a readiness declaration', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      aliceClient.getPreferences().crypto =
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());
      final rollout = CryptoRollout(aliceClient);

      await rollout.declareReady(namespace);
      expect(await rollout.publishNotReadyIfAbsent(namespace), isFalse);

      expect(
          await PublishedCapabilities(clientFor(bob, 'enroll-b'))
              .advertisedBy(alice, namespace),
          containsAll([nskeyCryptoProviderId, symmetricAesGcmCryptoProviderId]),
          reason: 'otherwise every restart would demote the atSign and the '
              'operator would have to keep re-declaring it');
    });

    test('a not-ready seeded deeper cannot undo readiness declared higher',
        () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      aliceClient.getPreferences().crypto =
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());
      final rollout = CryptoRollout(aliceClient);

      await rollout.declareReady('my_apps');

      expect(await rollout.publishNotReadyIfAbsent(namespace), isFalse,
          reason: 'the levels intersect, so seeding legacy-only at '
              'app_1.my_apps would silently demote the whole of my_apps');
    });

    test('readiness advertises everything this build reads', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      aliceClient.getPreferences().crypto =
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());

      await CryptoRollout(aliceClient).declareReady(namespace);

      expect(
          await PublishedCapabilities(clientFor(bob, 'enroll-b'))
              .advertisedBy(alice, namespace),
          {
            legacyCryptoProviderId,
            nskeyCryptoProviderId,
            symmetricAesGcmCryptoProviderId
          },
          reason: 'legacy stays in the set — it is never unregistered, because '
              'history has to keep opening');
    });

    test('withdrawing readiness returns the fleet to legacy only', () async {
      final aliceClient = clientFor(alice, 'enroll-a');
      aliceClient.getPreferences().crypto =
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());
      final rollout = CryptoRollout(aliceClient);
      final bobsView =
          PublishedCapabilities(clientFor(bob, 'enroll-b'), ttl: Duration.zero);

      await rollout.declareReady(namespace);
      expect(await bobsView.advertisedBy(alice, namespace),
          contains(symmetricAesGcmCryptoProviderId));

      await rollout.publishNotReady(namespace);

      expect(await bobsView.advertisedBy(alice, namespace),
          {legacyCryptoProviderId});
    });
  });
}
