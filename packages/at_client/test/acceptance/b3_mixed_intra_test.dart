/// B3 · Mixed-PQ within one atSign.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 10.
library;

import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';
  const pqPair = {nskeyCryptoProviderId, symmetricAesGcmCryptoProviderId};

  setUpAll(() => registerFallbackValue(AtKey()));

  /// `alice1` — an upgraded client: it reads the post-quantum path and writes
  /// whatever negotiation says its atSign's fleet can read.
  ({MockAtClient atClient, PublishedCapabilities markers}) alice1() {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    atClient.getPreferences()
      ..namespace = namespace
      ..crypto =
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());
    final markers = PublishedCapabilities(atClient);
    PublishedCapabilities.setForClient(atClient, markers);
    return (atClient: atClient, markers: markers);
  }

  AtKey selfKey(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = alice;

  /// The notification frame for a self notification — same key shape, same
  /// selection path. The row says "applies to put AND notify alike", and the
  /// two share exactly one decision point, so asserting the decision covers
  /// both without pretending a mock notification proves delivery.
  AtKey selfNotificationKey() => selfKey('heartbeat');

  group('B3 · mixed-PQ within one atSign', () {
    test(
        'UC-B3.1 · an upgraded enrollment still writes legacy for an '
        'un-upgraded sibling', () async {
      // GIVEN alice1 is PQ (holds the nskey and signing-root privates), alice2 is
      //       still legacy-only; @alice readiness = n-r.
      // WHEN  alice1 puts or notifies a self key both must read.
      // THEN  alice1 writes/notifies LEGACY — the scheme alice2 can read — until
      //       readiness flips. Migration invariant: write only what every reader
      //       supports. Applies to put AND notify alike.
      final c = alice1();
      c.markers.seed(alice, namespace, {legacyCryptoProviderId});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey('treaty')),
          legacyCryptoProviderId,
          reason: 'alice1 can read the post-quantum path and would rather '
              'write it — the marker is what stops it, because alice2 cannot');
      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfNotificationKey()),
          legacyCryptoProviderId,
          reason: 'put and notify alike: a notification alice2 cannot decrypt '
              'is as lost as a record it cannot read');
    });

    test('UC-B3.2 · readiness flips once all @alice enrollments are PQ',
        () async {
      // GIVEN all @alice enrollments now PQ; the operator (or auto-detect)
      //       flips readiness to ready.
      // WHEN  alice1 writes/notifies self data.
      // THEN  self data goes via the nskey data path — at/nskey conveys the CK
      //       and at/symmetric/AES/GCM encrypts the data; the data is never
      //       encapsulated directly to the nskey. No @alice
      //       enrollment loses access.
      final c = alice1();
      c.markers.seed(alice, namespace, {legacyCryptoProviderId, ...pqPair});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey('treaty')),
          symmetricAesGcmCryptoProviderId,
          reason: 'the flip is the marker, not a new build: the same client '
              'that wrote legacy a moment ago now writes the data path');
      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfNotificationKey()),
          symmetricAesGcmCryptoProviderId);

      // The data is encrypted under a content key and never encapsulated to
      // the nskey directly: the value routes to at/symmetric/AES/GCM, and
      // at/nskey is reached only by the conveyance, which asks for it by name.
      expect(
          await CryptoRuntime(c.atClient).negotiatedProviderIdFor(
              nskeyCryptoProviderId,
              atKey: selfKey('ck7.__ck')),
          nskeyCryptoProviderId);
    });
  });
}
