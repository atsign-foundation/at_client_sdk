import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// `disallowLegacyEncryption` — the flag that says never write new data under
/// the legacy provider: take a post-quantum path or refuse.
///
/// The whole value of the flag is in what it does *not* govern. A client that
/// refused legacy reads would lose its own history; one that refused
/// `shouldEncrypt = false` would break every deliberately-plaintext record. So
/// the tests below matter in both directions.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  setUpAll(() => registerFallbackValue(AtKey()));

  /// A client that refuses legacy encryption, with a seeded capability view.
  ({StrictMockAtClient atClient, PublishedCapabilities markers})
      strictClient() {
    final atClient = StrictMockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    atClient.getPreferences()
      ..namespace = namespace
      ..crypto =
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());
    final markers = PublishedCapabilities(atClient);
    PublishedCapabilities.setForClient(atClient, markers);
    return (atClient: atClient, markers: markers);
  }

  AtKey sharedKey() => AtKey()
    ..key = 'note'
    ..namespace = namespace
    ..sharedBy = alice
    ..sharedWith = bob;

  group('what it refuses', () {
    test('a destination only legacy can reach', () async {
      final c = strictClient();
      c.markers.seed(bob, namespace, {legacyCryptoProviderId});

      await expectLater(
          () => CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: sharedKey()),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'a legacy-only recipient is refused, never silently written '
              'in a scheme that can be harvested now and opened later');
    });

    test('an explicitly requested legacy write', () async {
      final c = strictClient();

      await expectLater(
          () => CryptoRuntime(c.atClient).negotiatedProviderIdFor(
              legacyCryptoProviderId,
              atKey: sharedKey()),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'an explicit request is honoured over negotiation, but not '
              'over the flag — the flag is the guarantee');
    });

    test('a write that reaches encryption still routed to legacy', () async {
      final c = strictClient();
      final key = sharedKey()
        ..metadata.appMetadata =
            AppMetadata(providerId: legacyCryptoProviderId);

      await expectLater(
          () => CryptoRuntime(c.atClient).encryptForPut(key, 'secret'),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'the second check is the point every encrypting write passes '
              'through, so the guarantee does not rest on each call path '
              'having remembered to ask');
    });

    test('a notification that reaches encryption routed to legacy', () async {
      final c = strictClient();
      final key = sharedKey()
        ..metadata.appMetadata =
            AppMetadata(providerId: legacyCryptoProviderId);

      await expectLater(
          () => CryptoRuntime(c.atClient).encryptForNotification(key, 'hi'),
          throwsA(isA<AtException>()));
    });

    test('the error names the record', () async {
      final c = strictClient();
      c.markers.seed(bob, namespace, {legacyCryptoProviderId});

      await expectLater(
          () => CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: sharedKey()),
          throwsA(predicate((e) => '$e'.contains('note'))));
    });
  });

  group('what it leaves alone', () {
    test('reading a legacy record', () async {
      final c = strictClient();
      final key = AtKey()
        ..key = 'note'
        ..namespace = namespace
        ..sharedBy = alice
        ..metadata = (Metadata()
          ..appMetadata = AppMetadata(providerId: legacyCryptoProviderId));

      // The legacy provider itself fails on this fixture for its own reasons —
      // no shared key, no atChops. What matters is that the refusal is NOT the
      // failure: history has to keep opening.
      await expectLater(
          () => CryptoRuntime(c.atClient).decryptForGet(key, 'ciphertext'),
          throwsA(isNot(isA<LegacyEncryptionRefusedException>())),
          reason: 'upgrading only ever adds read capability — a client that '
              'refused legacy reads would lose its own history');
    });

    test('a post-quantum write to a ready destination', () async {
      final c = strictClient();
      c.markers.seed(bob, namespace, {
        legacyCryptoProviderId,
        nskeyCryptoProviderId,
        symmetricAesGcmCryptoProviderId
      });

      expect(
          await CryptoRuntime(c.atClient)
              .negotiatedProviderIdFor(null, atKey: sharedKey()),
          symmetricAesGcmCryptoProviderId,
          reason: 'control: the flag refuses one scheme, it does not refuse '
              'writing');
    });
  });

  group('the switch it overrides', () {
    // The predicate the put pre-pass consults when a destination turns out to
    // have no post-quantum key at all.
    test('the cold-start legacy fallback does not survive it', () {
      expect(
          AtClientImpl.mayFallBackToLegacy(
              AtClientPreference(disallowLegacyEncryption: true)
                ..allowLegacyCryptoFallback = true),
          isFalse,
          reason: 'the two switches say opposite things and the flag wins — a '
              'cold start is refused rather than reached under legacy');
      expect(
          AtClientImpl.mayFallBackToLegacy(
              AtClientPreference()..allowLegacyCryptoFallback = true),
          isTrue,
          reason: 'control: without the flag the escape hatch still opens, or '
              'the arm above would prove nothing');
      expect(AtClientImpl.mayFallBackToLegacy(AtClientPreference()), isFalse,
          reason: 'and it is shut unless asked for');
      expect(AtClientImpl.mayFallBackToLegacy(null), isFalse);
    });
  });

  group('immutability', () {
    test('there is no setter', () {
      final preference = AtClientPreference(disallowLegacyEncryption: true);

      expect(preference.disallowLegacyEncryption, isTrue);
      // A flag governing what a client may write must not be flippable
      // mid-run, or "was that record written under the guarantee?" has no
      // answer. `final` is how that is enforced, and this asserts the default
      // stays where the era says it is.
      expect(AtClientPreference().disallowLegacyEncryption, isFalse);
    });
  });
}
