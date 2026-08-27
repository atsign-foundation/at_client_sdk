/// B3 · Mixed-PQ within one atSign — the two-release ladder itself.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 10 (rewritten 2026-08-05
/// for the app-decides model, `decisions.md` 36). There is no readiness marker
/// and no negotiation: what an install writes is decided by which build it
/// runs, and these rows assert the two builds' contracts at the one decision
/// point every put and notify share.
library;

import 'package:at_client/at_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'proven_elsewhere.dart';

import '../test_utils/mocks.dart';

void main() {
  const alice = '@alice';
  const namespace = 'app_1.my_apps';

  setUpAll(() => registerFallbackValue(AtKey()));

  MockAtClient clientWith(CryptoConfig config) {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    atClient.getPreferences()
      ..namespace = namespace
      ..crypto = config;
    return atClient;
  }

  AtKey selfKey(String name) => AtKey()
    ..key = name
    ..namespace = namespace
    ..sharedBy = alice;

  group('B3 · mixed-PQ within one atSign', () {
    test(
        'UC-B3.1 · a capability-stage enrollment reads PQ but still writes '
        'legacy', () {
      // GIVEN alice1 runs the app's capability build (era default: PQ
      //       providers registered, defaultProviderId legacy); a sibling
      //       install may still be on the previous build.
      // WHEN  alice1 puts or notifies a self key both must read.
      // THEN  alice1 writes/notifies LEGACY. Writing PQ is the ACTIVE
      //       release's decision, never the capability build's — which is what
      //       makes the capability build safe to roll out everywhere first.
      final atClient = clientWith(
          CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing()));

      expect(
          CryptoRuntime.providerIdFor(atClient, null, atKey: selfKey('treaty')),
          legacyCryptoProviderId,
          reason: 'this client can READ the post-quantum path — the ladder is '
              'what stops it writing one, not a capability it lacks');
      expect(
          CryptoRuntime.providerIdFor(atClient, null,
              atKey: selfKey('heartbeat')),
          legacyCryptoProviderId,
          reason: 'put and notify share this one decision point, so this '
              'covers both: a notification an old install cannot decrypt is '
              'as lost as a record it cannot read');

      provenIn(
        'packages/at_client/test/crypto_era_default_test.dart',
        'a NOTIFICATION at the era default reaches the legacy provider too',
        proves: 'the "applies to put and notify alike" half. The two '
            'assertions above are `providerIdFor` asked twice under two key '
            'names — the same call answered the same way, which is a claim '
            'about put restated rather than anything about notify. The notify '
            'entry point has its own refusal check and its own stamp, so that '
            'test drives it: put and notify both reach the LEGACY provider '
            '(read off its call count, not inferred), the post-quantum '
            'provider is registered and reached zero times, and the '
            'notification is stamped legacy so a sibling on the previous '
            'build reads it by the id it already knows. It is also the arm '
            'saying the capability stage does NOT refuse the notification — '
            'the pqActive contrast is in disallow_legacy_encryption_test.dart, '
            'where the identical call is refused. Mutation-proven twice: '
            'routing notify away from the put decision reddens the first, and '
            'dropping the stamp reddens the last',
        clauses: ['Applies to **put and notify** alike'],
      );

      // The "reads PQ" half, stated as the registered set rather than assumed:
      // both PQ providers resolve, so a record arriving stamped with either id
      // routes. The decrypt itself is proven by the data-path suites.
      final config = CryptoConfig.forClient(atClient);
      expect(config.lookup(nskeyCryptoProviderId), isNotNull);
      expect(config.lookup(symmetricAesGcmCryptoProviderId), isNotNull);
    });

    test(
        'UC-B3.2 · the app\'s active release flips self data to the nskey '
        'path', () {
      // GIVEN the app ships its active build (4.x default, or an explicit
      //       AtClientPreference.crypto); every install has run the capability
      //       build first (the release-ordering discipline).
      // WHEN  alice1 writes/notifies self data.
      // THEN  self data goes via the nskey data path — the CK is conveyed by
      //       at/nskey and the data encrypted by at/symmetric/AES/GCM; the
      //       data is never encapsulated directly to the nskey. Capability-
      //       stage installs read it (reads are universal).
      final atClient =
          clientWith(CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()));

      expect(
          CryptoRuntime.providerIdFor(atClient, null, atKey: selfKey('treaty')),
          symmetricAesGcmCryptoProviderId,
          reason: 'the flip is the app\'s release, nothing else: same SDK, '
              'same key material, different build default');
      expect(
          CryptoRuntime.providerIdFor(atClient, null,
              atKey: selfKey('heartbeat')),
          symmetricAesGcmCryptoProviderId);

      // The data value routes to the symmetric provider; at/nskey is reached
      // only by the conveyance, which asks for it by name — the data is never
      // encapsulated to the nskey directly.
      expect(
          CryptoRuntime.providerIdFor(atClient, nskeyCryptoProviderId,
              atKey: selfKey('ck7.__ck')),
          nskeyCryptoProviderId);

      // And the round trip a capability-stage sibling performs on this data is
      // the data-path suites' business, proven live:
      // `nskey_data_path_live_test.dart` (functional) and
      // `era_default_read_test.dart` (e2e) — a client with no config at all
      // opens what an active client sealed.
      provenIn(
        'tests/at_functional_test/test/nskey_data_path_live_test.dart',
        'a self value round-trips through the nskey data path',
        proves: 'the routing this row asserts, against a live atServer: the '
            'content key travels in its own conveyance sealed to the nskey '
            'and the value is encrypted symmetrically citing that key by '
            'ckKid. The value record carries no sealedKey, which is what '
            'rules out the data having been encapsulated to the nskey '
            'directly',
        clauses: ['the data is never encapsulated directly to the nskey'],
      );
    });
  });
}
