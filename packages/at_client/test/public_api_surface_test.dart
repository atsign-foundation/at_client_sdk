/// Everything the public API *requires* must be nameable from the barrel.
///
/// This file imports `package:at_client/at_client.dart` and nothing else — no
/// `src/` paths, no `implementation_imports` ignore. That constraint is the
/// test: `CryptoConfig.nskey` is an exported factory with a **required**
/// `NskeyKeyRing`, and the CHANGELOG tells callers to catch
/// `ContentKeyUnavailableException` and to name provider ids. If any of those
/// stops being exported, this file stops compiling.
library;

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

void main() {
  group('the nskey surface is reachable through the barrel', () {
    test('CryptoConfig.nskey can be constructed by an outside caller', () {
      // An app can only do this if NskeyKeyRing and a concrete ring are both
      // exported — the required parameter type is what made this impossible.
      final NskeyKeyRing ring = InMemoryNskeyKeyRing();
      final config = CryptoConfig.nskey(keyRing: ring);

      expect(config.defaultProviderId, symmetricAesGcmCryptoProviderId);
      expect(config.lookup(nskeyCryptoProviderId), isNotNull);
      expect(config.lookup(symmetricAesGcmCryptoProviderId), isNotNull);
    });

    test('the retryable-read exception is nameable', () {
      final e = ContentKeyUnavailableException('kid', 'not here yet');
      expect(e, isA<AtDecryptionException>());
      expect(e.ckKid, 'kid');
    });

    test('the provider ids and family prefix are nameable', () {
      expect(nskeyCryptoProviderId, startsWith(nskeyProviderFamily));
      expect(legacyCryptoProviderId, isNotEmpty);
      expect(NskeyRecipientKind.nskey, isNotEmpty);
    });

    test('the published key ring and its verifier seam are nameable', () {
      expect(nskeyAdvertisementKey('@alice', 'wavi').key, '__nskey');
      final AdvertisedKeyVerifier verifier = UnverifiedAdvertisedKeys();
      expect(verifier, isNotNull);
    });
  });
}
