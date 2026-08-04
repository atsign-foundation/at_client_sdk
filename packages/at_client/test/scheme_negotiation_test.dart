import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Scheme negotiation — "write only what every required reader supports".
///
/// The migration turns on this one decision. Get it wrong in the permissive
/// direction and an upgraded client locks an un-upgraded sibling out of data it
/// is supposed to share; get it wrong in the conservative direction and the
/// post-quantum path never switches on however much of the fleet is ready.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  const pqPair = {nskeyCryptoProviderId, symmetricAesGcmCryptoProviderId};

  setUpAll(() => registerFallbackValue(AtKey()));

  /// A client of [alice] with the era default — reads the post-quantum path,
  /// writes legacy — and a seeded capability view so nothing hits an atServer.
  ({MockAtClient atClient, PublishedCapabilities markers}) client(
      {CryptoConfig? crypto}) {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    atClient.getPreferences()
      ..namespace = namespace
      ..crypto = crypto ??
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());
    final markers = PublishedCapabilities(atClient);
    PublishedCapabilities.setForClient(atClient, markers);
    return (atClient: atClient, markers: markers);
  }

  AtKey selfKey() => AtKey()
    ..key = 'note'
    ..namespace = namespace
    ..sharedBy = alice;

  AtKey sharedKey() => AtKey()
    ..key = 'note'
    ..namespace = namespace
    ..sharedBy = alice
    ..sharedWith = bob;

  group('a fleet that has not declared readiness', () {
    test('keeps an era-default client writing legacy', () async {
      final c = client();
      c.markers.seed(alice, namespace, {legacyCryptoProviderId});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          legacyCryptoProviderId,
          reason: 'UC-B3.1: a sibling enrollment may still be an old build, so '
              'the upgraded one writes what that sibling can read');
    });

    test('demotes a client configured to write post-quantum', () async {
      final c =
          client(crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));
      c.markers.seed(bob, namespace, {legacyCryptoProviderId});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: sharedKey()),
          legacyCryptoProviderId,
          reason: 'UC-B4.1: bob says legacy-only, so no write goes out that '
              'bob cannot read — whatever this client would rather write');
    });

    test(
        'a fleet advertising the data scheme but not the conveyance is not '
        'ready', () async {
      final c = client();
      // A reader that can resolve `at/symmetric/AES/GCM` but not the
      // `at/nskey` conveyance sees every value and opens none: the content key
      // never travels on the value itself.
      c.markers.seed(alice, namespace,
          {legacyCryptoProviderId, symmetricAesGcmCryptoProviderId});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          legacyCryptoProviderId,
          reason: 'a provider id names every algorithm a reader needs code '
              'for, but a scheme can still need a second provider registered');
    });
  });

  group('a fleet that has declared readiness', () {
    test('flips an era-default client to the nskey data path', () async {
      final c = client();
      c.markers.seed(alice, namespace, {legacyCryptoProviderId, ...pqPair});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          symmetricAesGcmCryptoProviderId,
          reason: 'UC-B3.2: the marker is what moves the write side, with no '
              'new build and no flag day');
    });

    test('flips a cross-atSign share the moment the recipient is ready',
        () async {
      final c = client();
      c.markers.seed(bob, namespace, {legacyCryptoProviderId, ...pqPair});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: sharedKey()),
          symmetricAesGcmCryptoProviderId,
          reason: 'UC-B4.4');
    });

    test('a ready recipient does not flip the sender\'s own self records',
        () async {
      final c = client();
      c.markers.seed(bob, namespace, {legacyCryptoProviderId, ...pqPair});
      c.markers.seed(alice, namespace, {legacyCryptoProviderId});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: sharedKey()),
          symmetricAesGcmCryptoProviderId);
      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          legacyCryptoProviderId,
          reason: 'UC-B4.3: two directions, two schemes, one put — the record '
              'shared with bob is read by bob\'s fleet, alice\'s self records '
              'by hers, and they are negotiated apart');
    });

    test('an app pinned to legacy stays legacy however ready the fleet is',
        () async {
      final c = client(crypto: const CryptoConfig.legacy());
      c.markers.seed(alice, namespace, {legacyCryptoProviderId, ...pqPair});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          legacyCryptoProviderId,
          reason: 'negotiation reads a marker to choose among the schemes this '
              'client registered; it can never be told to write one it has no '
              'code for');
    });
  });

  group('no marker at all', () {
    test('leaves the configured default untouched', () async {
      final c =
          client(crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: sharedKey()),
          symmetricAesGcmCryptoProviderId,
          reason: 'no evidence is not evidence of legacy: an app that has '
              'deliberately configured the post-quantum path is not silently '
              'demoted by a destination that has published nothing');
    });

    test('does not promote an era-default client', () async {
      final c = client();

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          legacyCryptoProviderId,
          reason: 'the era default writes legacy until a marker says the whole '
              'fleet can read something better');
    });
  });

  group('where the answers come from', () {
    test(
        'the client\'s current capability view, not the one that existed at '
        'the first write', () async {
      // A client does several writes during start-up, before an app — or a
      // test — has had any chance to supply its own capability view. The
      // negotiator is cached per client and outlives any one write, so
      // capturing the view at construction pinned it to whatever existed then:
      // CryptoRollout would read a fresh marker while the write path kept
      // answering from an instance nobody could reach. Caught by a live
      // two-atSign run, where a declared readiness never moved a single write.
      final c = client();
      c.markers.seed(alice, namespace, {legacyCryptoProviderId});
      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          legacyCryptoProviderId,
          reason: 'this first write is what creates the cached negotiator');

      // Now the client's view is replaced — the shape of an operator flip seen
      // through a fresh fetch.
      final flipped = PublishedCapabilities(c.atClient)
        ..seed(alice, namespace, {legacyCryptoProviderId, ...pqPair});
      PublishedCapabilities.setForClient(c.atClient, flipped);

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: selfKey()),
          symmetricAesGcmCryptoProviderId);
    });
  });

  group('what is never negotiated', () {
    test('an explicitly requested scheme', () async {
      final c = client();
      c.markers.seed(alice, namespace, {legacyCryptoProviderId});

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(nskeyCryptoProviderId, atKey: selfKey()),
          nskeyCryptoProviderId,
          reason: 'the content-key conveyance is routed explicitly to '
              'at/nskey, and negotiating THAT record down to legacy would '
              'break the very write it exists to serve');
    });

    test('a key with no namespace', () async {
      final c = client();
      c.markers.seed(alice, namespace, {legacyCryptoProviderId, ...pqPair});
      final noNamespace = AtKey()
        ..key = 'shared_key.bob'
        ..sharedBy = alice
        ..metadata = (Metadata()..namespaceAware = false);

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: noNamespace),
          legacyCryptoProviderId,
          reason: 'the SDK\'s own internal records carry no namespace, so '
              'there is nothing to look a marker up by — and the nskey path is '
              '(owner, namespace) scoped and declines them anyway');
    });
  });
}
