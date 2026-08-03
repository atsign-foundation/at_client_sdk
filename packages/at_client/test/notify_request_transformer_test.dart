import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_client/src/transformer/request_transformer/notify_request_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Notify has to reach the same provider `put` would for the same key.
///
/// The two paths resolve the namespace at different points, and provider
/// selection is namespace-sensitive: the nskey path is `(owner, namespace)`
/// scoped and declines a key without one. Selecting before the namespace is
/// filled in therefore picks legacy for every key that relies on the
/// preference default — silently, at `finer`, while `put` on the identical key
/// picks nskey. An app would believe a channel is post-quantum when it is not.
void main() {
  const owner = '@alice';
  const namespace = 'wavi'; // MockAtClient's preference namespace

  late XWingKeyPair aliceNskey;
  late XWingKeyPair bobNskey;

  setUpAll(() async {
    aliceNskey = await XWingKeyPair.generate();
    bobNskey = await XWingKeyPair.generate();
    registerFallbackValue(AtKey());
  });

  /// A mock client configured for the nskey path, with `put` wired the way the
  /// real pipeline wires it: the conveyance record routes to `at/nskey`, whose
  /// encrypt seals the CK.
  ({MockAtClient atClient, List<AtKey> written}) nskeyClient() {
    final ring = InMemoryNskeyKeyRing()
      ..seedKeypair(owner, namespace,
          publicKey: aliceNskey.publicKeyBytes,
          privateKey: aliceNskey.privateKeyBytes)
      ..seedPublicOnly('@bob', namespace, publicKey: bobNskey.publicKeyBytes);

    final config = CryptoConfig.nskey(keyRing: ring);
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(owner);
    atClient.getPreferences()
      ..namespace = namespace
      ..crypto = config;

    final written = <AtKey>[];
    final nskey = config.lookup(nskeyCryptoProviderId)!;
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      final key = inv.positionalArguments[0] as AtKey;
      final value = inv.positionalArguments[1] as String;
      written.add(key);
      await nskey.encrypt(CryptoContext(atClient: atClient), key, value);
      return true;
    });

    return (atClient: atClient, written: written);
  }

  group('provider selection happens after the namespace is resolved', () {
    test('a key relying on the preference namespace still reaches nskey',
        () async {
      final c = nskeyClient();
      final atKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob'
        ..sharedBy = owner;
      // NotificationServiceImpl.notify sets this before it calls transform.
      atKey.metadata.isEncrypted = true;
      final params = NotificationParams.forUpdate(atKey, value: '555');

      await NotificationRequestTransformer(c.atClient).transform(params);

      expect(params.atKey.namespace, namespace,
          reason: 'the preference namespace must be applied');
      expect(params.atKey.metadata.appMetadata?.providerId,
          symmetricAesGcmCryptoProviderId,
          reason: 'notify must pick the same provider put would for this key; '
              'falling back to legacy here is a silent crypto downgrade');
    });

    test('the preparation step runs, so a content key is conveyed', () async {
      final c = nskeyClient();
      final params = NotificationParams.forUpdate(
          AtKey()
            ..key = 'phone'
            ..sharedWith = '@bob'
            ..sharedBy = owner
            ..metadata = (Metadata()..isEncrypted = true),
          value: '555');

      await NotificationRequestTransformer(c.atClient).transform(params);

      expect(c.written, hasLength(1),
          reason: 'a namespace-less key makes CkManager.ensureCurrent bail, so '
              'no conveyance is written and nothing can decrypt the value');
      expect(c.written.single.key, endsWith('.__ck'));
      expect(c.written.single.namespace, namespace);
    });

    test('a key that already carries its own namespace is unaffected',
        () async {
      final c = nskeyClient();
      final params = NotificationParams.forUpdate(
          AtKey()
            ..key = 'phone'
            ..namespace = namespace
            ..sharedWith = '@bob'
            ..sharedBy = owner
            ..metadata = (Metadata()..isEncrypted = true),
          value: '555');

      await NotificationRequestTransformer(c.atClient).transform(params);

      expect(params.atKey.metadata.appMetadata?.providerId,
          symmetricAesGcmCryptoProviderId);
    });
  });
}
