import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
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

  /// A client that refuses legacy encryption. Its crypto config decides what
  /// it *would* write; the flag decides what it may.
  StrictMockAtClient strictClient({CryptoConfig? crypto}) {
    final atClient = StrictMockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    atClient.getPreferences()
      ..namespace = namespace
      ..crypto = crypto ?? const CryptoConfig.legacy();
    return atClient;
  }

  AtKey sharedKey() => AtKey()
    ..key = 'note'
    ..namespace = namespace
    ..sharedBy = alice
    ..sharedWith = bob;

  group('what it refuses', () {
    test('a client configured to write legacy', () {
      final atClient = strictClient();

      expect(
          () => CryptoRuntime.providerIdFor(atClient, null, atKey: sharedKey()),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'the era default writes legacy, and under the flag that is '
              'refused at selection — before anything is composed or in '
              'flight');
    });

    test('an explicitly requested legacy write', () {
      final atClient = strictClient(
          crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));

      expect(
          () => CryptoRuntime.providerIdFor(atClient, legacyCryptoProviderId,
              atKey: sharedKey()),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'an explicit request is honoured over the default, but not '
              'over the flag — the flag is the guarantee');
    });

    test('a key the PQ provider declines, whose fallback is legacy', () {
      final atClient = strictClient(
          crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));
      // No namespace: the nskey path is (owner, namespace)-scoped and declines
      // it, so the defaulted id falls back to legacy — which the flag refuses.
      final internalKey = AtKey()
        ..key = 'shared_key.bob'
        ..sharedBy = alice
        ..metadata = (Metadata()..namespaceAware = false);

      expect(
          () => CryptoRuntime.providerIdFor(atClient, null, atKey: internalKey),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'the decline-fallback is a legacy write like any other; '
              'letting it through would make the guarantee leak through '
              'every namespace-less internal record');
    });

    test('a write that reaches encryption still routed to legacy', () async {
      final atClient = strictClient();
      final key = sharedKey()
        ..metadata.appMetadata =
            AppMetadata(providerId: legacyCryptoProviderId);

      await expectLater(
          () => CryptoRuntime(atClient).encryptForPut(key, 'secret'),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'the second check is the point every encrypting write passes '
              'through, so the guarantee does not rest on each call path '
              'having remembered to ask');
    });

    test('a notification that reaches encryption routed to legacy', () async {
      final atClient = strictClient();
      final key = sharedKey()
        ..metadata.appMetadata =
            AppMetadata(providerId: legacyCryptoProviderId);

      await expectLater(
          () => CryptoRuntime(atClient).encryptForNotification(key, 'hi'),
          throwsA(isA<AtException>()));
    });

    test('the error names the record', () {
      final atClient = strictClient();

      expect(
          () => CryptoRuntime.providerIdFor(atClient, null, atKey: sharedKey()),
          throwsA(predicate((e) => '$e'.contains('note'))));
    });
  });

  group('what it leaves alone', () {
    test('reading a legacy record', () async {
      final atClient = strictClient();
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
          () => CryptoRuntime(atClient).decryptForGet(key, 'ciphertext'),
          throwsA(isNot(isA<LegacyEncryptionRefusedException>())),
          reason: 'upgrading only ever adds read capability — a client that '
              'refused legacy reads would lose its own history');
    });

    test('a post-quantum write', () {
      final atClient = strictClient(
          crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));

      expect(CryptoRuntime.providerIdFor(atClient, null, atKey: sharedKey()),
          symmetricAesGcmCryptoProviderId,
          reason: 'control: the flag refuses one scheme, it does not refuse '
              'writing — an app that writes the PQ path is untouched');
    });
  });

  /// A `local:` record is never synced to the atServer, so the
  /// harvest-now-decrypt-later premise the flag exists for has no referent.
  /// Before this carve-out every post-quantum provider declined a local key,
  /// the defaulted id fell back to legacy, and the flag refused it — which made
  /// the SDK's own watermarks unwritable and took the notification listener out
  /// with them.
  group('local: keys', () {
    AtKey watermark() => AtKey.local('lastreceivednotification', alice,
            namespace: namespace)
        .build();

    test('a local key is not refused', () {
      final atClient = strictClient(
          crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));

      expect(
          CryptoRuntime.providerIdFor(atClient, null, atKey: watermark()),
          legacyCryptoProviderId,
          reason: 'the nskey path is (owner, namespace)-scoped and declines a '
              'local key, so the id still falls back to legacy — but the '
              'record never leaves the device, so there is nothing to harvest '
              'and nothing to refuse');
    });

    test('nor at encryption time', () async {
      final atClient = strictClient();
      final key = watermark()
        ..metadata.appMetadata =
            AppMetadata(providerId: legacyCryptoProviderId);

      // The legacy provider fails on this fixture for its own reasons (no
      // atChops). What matters is that the refusal is not the failure.
      await expectLater(
          () => CryptoRuntime(atClient).encryptForPut(key, 'secret'),
          throwsA(isNot(isA<LegacyEncryptionRefusedException>())),
          reason: 'the second check is a separate call site and carries the '
              'same carve-out, or the guarantee would depend on which one the '
              'write happened to reach');
    });

    test('the carve-out is isLocal, NOT "it lands on self encryption"', () {
      final atClient = strictClient(
          crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));
      // A synced self key: no namespace, so the nskey path declines it and the
      // fallback is legacy — exactly as for a local key, and it reaches the
      // very same encryption class. The difference that matters is that the
      // atServer holds this one, so it IS harvestable.
      final syncedSelfKey = AtKey()
        ..key = 'phone'
        ..sharedBy = alice
        ..metadata = (Metadata()..namespaceAware = false);

      expect(LegacyEncryption.build(syncedSelfKey, atClient),
          isA<SelfKeyEncryption>(),
          reason: 'the premise: this reaches the same AES-256-CTR-under-the-'
              'self-key path a local: record does, or the refusal below would '
              'be about something else entirely');
      expect(
          () =>
              CryptoRuntime.providerIdFor(atClient, null, atKey: syncedSelfKey),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'and it is still refused — exempting on the encryption class '
              'rather than on isLocal would silently widen the carve-out to '
              'every synced self key, which the atServer does hold');
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
