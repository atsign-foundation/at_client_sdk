import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The era default: which crypto config a client encrypts and decrypts under
/// when the app never named one.
///
/// The release sequence is what this encodes. A final-3.x client **reads** PQ
/// records — a record arrives stamped with the provider that wrote it, so a
/// client that cannot resolve that id fails on data someone already sent it —
/// while still **writing** legacy, because the first client to write PQ produces
/// records every other client must already be able to read. Read side first
/// everywhere, write side flipped once, at 4.x.
void main() {
  late MockAtClient client;

  setUp(() {
    // A fresh preference holds the CryptoConfig.eraDefault() marker — the
    // "app named nothing" state under test here.
    client = MockAtClient();
  });

  CryptoConfig eraConfig() =>
      CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());

  test('the era default reads nskey but writes legacy', () {
    CryptoConfig.adoptEraDefault(client, eraConfig());
    final resolved = CryptoConfig.forClient(client);

    expect(resolved.defaultProviderId, legacyCryptoProviderId,
        reason: 'writes stay legacy until 4.x — flipping this is a fleet-wide '
            'commitment, not a per-client one');
    expect(resolved.lookup(nskeyCryptoProviderId), isNotNull);
    expect(resolved.lookup(symmetricAesGcmCryptoProviderId), isNotNull,
        reason: 'an inbound PQ record names this provider; a client that '
            'cannot resolve it fails on data already sent to it');
  });

  test('the untouched preference holds the eraDefault marker', () {
    expect(
        client.getPreferences().crypto, same(const CryptoConfig.eraDefault()),
        reason: 'the field is non-nullable (published 3.14.0 shape), so this '
            'marker — not null — is how the SDK tells "app named nothing"');

    CryptoConfig.adoptEraDefault(client, eraConfig());
    expect(
        CryptoConfig.forClient(client).lookup(symmetricAesGcmCryptoProviderId),
        isNotNull,
        reason: 'the marker means no choice: the era set must resolve through '
            'it exactly as it did through null');
  });

  test('naming CryptoConfig.legacy() is an opt-out, not the default', () {
    client.getPreferences().crypto = const CryptoConfig.legacy();

    CryptoConfig.adoptEraDefault(client, eraConfig());

    expect(CryptoConfig.forClient(client).providers, isEmpty,
        reason: 'an app that deliberately pinned legacy must hold it — the '
            'marker and CryptoConfig.legacy() are distinct values even though '
            'they behave identically when read as a config');
    expect(CryptoConfig.eraDefaultFor(client), isNull);
  });

  test('the marker read as a config degrades to the published legacy shape',
      () {
    // External code compiled against 3.14.0 reads preference.crypto directly
    // (the field defaulted to CryptoConfig.legacy() there). The marker must
    // answer those reads with exactly that shape, or restoring non-nullability
    // would change behaviour for the very callers it exists to keep working.
    expect(const CryptoConfig.eraDefault().defaultProviderId,
        legacyCryptoProviderId);
    expect(const CryptoConfig.eraDefault().providers, isEmpty);
  });

  test('an app that named its own config keeps it', () {
    final mine = CryptoConfig(defaultProviderId: 'custom');
    client.getPreferences().crypto = mine;

    CryptoConfig.adoptEraDefault(client, eraConfig());

    expect(CryptoConfig.forClient(client), same(mine),
        reason: 'the SDK owns the default, never the override');
    expect(CryptoConfig.eraDefaultFor(client), isNull,
        reason: 'and it does not squirrel one away to surprise a later reader');
  });

  test('two clients get their own provider instances', () {
    final other = MockAtClient();

    CryptoConfig.adoptEraDefault(client, eraConfig());
    CryptoConfig.adoptEraDefault(other, eraConfig());

    expect(
        CryptoConfig.forClient(client).lookup(symmetricAesGcmCryptoProviderId),
        isNot(same(CryptoConfig.forClient(other)
            .lookup(symmetricAesGcmCryptoProviderId))),
        reason: 'these providers hold per-atSign state — one shared instance '
            'would let two atSigns read each other\'s cached content keys');
  });

  test('adopting twice keeps the first set', () {
    final first = eraConfig();
    CryptoConfig.adoptEraDefault(client, first);
    CryptoConfig.adoptEraDefault(client, eraConfig());

    expect(CryptoConfig.forClient(client), same(first),
        reason: 'a re-used cached client must keep the content-key cache and '
            'key ring it was built with, or a restart silently loses them');
  });

  test('a client never given one falls back to legacy', () {
    expect(CryptoConfig.forClient(client).defaultProviderId,
        legacyCryptoProviderId);
    expect(CryptoConfig.forClient(client).providers, isEmpty);
    expect(
        CryptoConfig.forClient(null).defaultProviderId, legacyCryptoProviderId);
  });

  test('the nskey factory is the 4.x shape: PQ writes', () {
    expect(
        CryptoConfig.nskey(keyRing: InMemoryNskeyKeyRing()).defaultProviderId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the two factories differ only in the write default, and that '
            'difference is the whole 3.x-to-4.x step');
  });
}
