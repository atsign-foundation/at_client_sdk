import 'package:at_auth/at_auth.dart' show EnrollmentKeyExchangeMode;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/legacy/legacy_encryption.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// `disallowLegacyEncryption` — the flag that says never write new data under
/// the legacy provider: take a post-quantum path or refuse.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  setUpAll(() => registerFallbackValue(AtKey()));

  /// A client that refuses legacy encryption.
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
    test('a client configured to write with the legacy provider', () {
      final atClient = strictClient();

      expect(
          () => CryptoRuntime.providerIdFor(atClient, null, atKey: sharedKey()),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason:
              'the era default writes with the legacy provider, and under the flag that is '
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

    /// Exactly the key `NotificationService.send()` builds, where
    /// `AtKey.fromString` splits at the last dot and so hands back a null
    /// namespace for a single-segment one.
    ///
    /// Not interchangeable with a hand-built key: no caller produces one, so
    /// the refusal would say nothing about reachability.
    AtKey sendKey(String namespace) {
      final atKey = AtKey.fromString('$bob:$namespace$alice');
      atKey.metadata.namespaceAware = false;
      return atKey;
    }

    test(
        'a key the PQ provider declines, whose fallback is the legacy provider',
        () {
      final atClient = strictClient(
          crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));

      expect(
          () => CryptoRuntime.providerIdFor(atClient, null,
              atKey: sendKey('wavi')),
          throwsA(isA<LegacyEncryptionRefusedException>()),
          reason: 'the decline-fallback is a legacy write like any other; '
              'letting it through would make the guarantee leak through '
              'every namespace-less record');

      expect(
          CryptoRuntime.providerIdFor(atClient, null,
              atKey: sendKey('buzz.wavi')),
          symmetricAesGcmCryptoProviderId);
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

      // NOTE: the legacy provider fails on this fixture anyway — no shared
      // key, no atChops — so assert on which failure, not that one happened.
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
  group('local: keys', () {
    AtKey watermark() =>
        AtKey.local('lastreceivednotification', alice, namespace: namespace)
            .build();

    test('a local key is not refused', () {
      final atClient = strictClient(
          crypto: CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));

      expect(CryptoRuntime.providerIdFor(atClient, null, atKey: watermark()),
          legacyCryptoProviderId,
          reason: 'the nskey path is (owner, namespace)-scoped and declines a '
              'local key, so the id still falls back to the legacy provider — but the '
              'record never leaves the device, so there is nothing to harvest '
              'and nothing to refuse');
    });

    test('nor at encryption time', () async {
      final atClient = strictClient();
      final key = watermark()
        ..metadata.appMetadata =
            AppMetadata(providerId: legacyCryptoProviderId);

      // NOTE: the legacy provider fails on this fixture anyway (no atChops),
      // so assert on which failure, not that one happened.
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
    test('the cold-start legacy fallback does not survive it', () {
      expect(
          AtClientImpl.mayFallBackToLegacy(
              AtClientPreference(posture: PqPosture.pqActive)
                ..allowLegacyCryptoFallback = true),
          isFalse,
          reason: 'the two switches say opposite things and the flag wins — a '
              'cold start is refused rather than reached with the legacy provider');
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
    test('there is no setter, and no constructor argument either', () {
      final preference = AtClientPreference(posture: PqPosture.pqActive);

      expect(preference.disallowLegacyEncryption, isTrue);
      expect(AtClientPreference().disallowLegacyEncryption, isFalse);
    });

    test('the only way to set it is a posture that writes post-quantum', () {
      expect(
          PqPosture(
            authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
            dataSigningKeyAlgorithms: const {},
            seedNamespaceKeys: false,
            keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
            writesPqByDefault: true,
            configuresPqProviders: true,
            disallowLegacyEncryption: true,
            mintLegacyMaterial: true,
            sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
            keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
          ).disallowLegacyEncryption,
          isTrue,
          reason: 'a bespoke posture can still ask for the refusal without '
              'adopting the whole of pqActive');
      expect(
          () => PqPosture(
                authenticationKeyAlgorithm: SigningAlgoType.rsa2048,
                dataSigningKeyAlgorithms: const {},
                seedNamespaceKeys: false,
                keyExchangeMode: EnrollmentKeyExchangeMode.legacy,
                writesPqByDefault: false,
                configuresPqProviders: true,
                disallowLegacyEncryption: true,
                mintLegacyMaterial: true,
                sealsToKeyAlgorithms: SecretSharingAlgos.keyAlgos,
                keyEstablishmentAlgorithms: const [SecretSharingAlgos.xWing],
              ),
          throwsArgumentError);
    });
  });
}
