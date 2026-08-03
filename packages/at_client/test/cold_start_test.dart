import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Cold start — writing to a destination that has never used the namespace.
///
/// There is nothing to seal to and no post-quantum fallback: the only
/// atSign-level key is a signing root, which cannot receive an encapsulation.
/// So the write fails, and the three things that matter are that it fails *by
/// name* (an app must be able to say "@bob hasn't enabled this" rather than
/// report an encryption error), that the same question can be asked *before*
/// anything is composed, and that the legacy escape hatch stays shut unless the
/// app deliberately opened it.
void main() {
  const alice = '@alice';
  const bob = '@bob';
  const namespace = 'app_1.my_apps';

  late XWingKeyPair bobNskey;

  setUpAll(() async {
    bobNskey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  ({MockAtClient atClient, InMemoryNskeyKeyRing ring}) client() {
    final ring = InMemoryNskeyKeyRing();
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    atClient.getPreferences().namespace = namespace;
    atClient.getPreferences().crypto = CryptoConfig.nskey(keyRing: ring);
    return (atClient: atClient, ring: ring);
  }

  group('the readiness query', () {
    test('says no for a destination that has never used the namespace',
        () async {
      final c = client();

      expect(
          await CryptoRuntime(c.atClient).isReadyFor(bob, namespace), isFalse,
          reason: 'asking first is what lets an app say so up front, instead '
              'of discovering it when the send fails');
    });

    test('says yes once the destination has published a key', () async {
      final c = client();
      c.ring.seedPublicOnly(bob, namespace, publicKey: bobNskey.publicKeyBytes);

      expect(
          await CryptoRuntime(c.atClient).isReadyFor(bob, namespace), isTrue);
    });

    test('says yes for a scheme with no such precondition', () async {
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(alice);
      atClient.getPreferences().crypto = const CryptoConfig.legacy();

      expect(await CryptoRuntime(atClient).isReadyFor(bob, namespace), isTrue,
          reason: 'legacy encrypts to a public key every atSign has, so there '
              'is nothing to be unready for');
    });

    test('says yes when no config is named at all', () async {
      final atClient = MockAtClient();
      when(() => atClient.getCurrentAtSign()).thenReturn(alice);

      expect(await CryptoRuntime(atClient).isReadyFor(bob, namespace), isTrue,
          reason: 'the SDK default for this release is legacy');
    });
  });

  group('the write itself', () {
    /// The pre-pass the put pipeline runs before anything is in flight.
    Future<void> prepare(MockAtClient atClient, AtKey atKey) =>
        CryptoRuntime(atClient).prepareForPut(
            atKey, CryptoRuntime.providerIdFor(atClient, null, atKey: atKey));

    AtKey toBob(String name) => AtKey()
      ..key = name
      ..namespace = namespace
      ..sharedWith = bob
      ..sharedBy = alice;

    test('refuses by name, carrying the atSign and namespace', () async {
      final c = client();

      await expectLater(
        prepare(c.atClient, toBob('treaty')),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.atSign, 'atSign', bob)
            .having((e) => e.namespace, 'namespace', namespace)),
      );
    });

    test('the refusal is an encryption exception, so nothing escapes uncaught',
        () async {
      final c = client();

      await expectLater(prepare(c.atClient, toBob('treaty')),
          throwsA(isA<AtEncryptionException>()));
    });

    test('a self write to an unminted namespace refuses the same way',
        () async {
      final c = client();

      await expectLater(
        prepare(
            c.atClient,
            AtKey()
              ..key = 'diary'
              ..namespace = namespace
              ..sharedBy = alice),
        throwsA(isA<NamespaceKeyUnavailableException>()
            .having((e) => e.atSign, 'atSign', alice)),
        reason: 'the owner is as unreachable as a peer until her own namespace '
            'key exists',
      );
    });
  });

  group('the legacy escape hatch', () {
    test('is shut by default', () {
      expect(AtClientPreference().allowLegacyCryptoFallback, isFalse,
          reason: 'a silent downgrade to RSA is what the post-quantum work '
              'exists to prevent — the write succeeds, the app looks healthy, '
              'and the data is harvestable');
    });
  });
}
