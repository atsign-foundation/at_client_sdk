import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// The era default: which crypto config a client encrypts and decrypts under
/// when the app never named one.
void main() {
  late MockAtClient client;

  setUp(() {
    client = MockAtClient();
  });

  CryptoConfig eraConfig() =>
      CryptoConfig.readsNskeyWritesLegacy(keyRing: InMemoryNskeyKeyRing());

  test('the era default reads nskey but writes with the legacy provider', () {
    CryptoConfig.adoptEraDefault(client, eraConfig());
    final resolved = CryptoConfig.forClient(client);

    expect(resolved.defaultProviderId, legacyCryptoProviderId,
        reason:
            'writes stay with the legacy provider until 4.x — flipping this is a fleet-wide '
            'commitment, not a per-client one');
    expect(resolved.lookup(nskeyCryptoProviderId), isNotNull);
    expect(resolved.lookup(symmetricAesGcmCryptoProviderId), isNotNull,
        reason: 'an inbound PQ record names this provider; a client that '
            'cannot resolve it fails on data already sent to it');
  });

  test('a NOTIFICATION at the era default reaches the legacy provider too',
      () async {
    // UC-B3.1: the capability stage writes with the legacy provider for put and notify alike.
    final legacy = _Recorder(legacyCryptoProviderId);
    final pq = _Recorder(symmetricAesGcmCryptoProviderId);
    client.getPreferences().crypto = CryptoConfig(
        defaultProviderId: legacyCryptoProviderId, providers: [legacy, pq]);

    final notified = AtKey()..metadata = Metadata();
    final put = AtKey()..metadata = Metadata();

    final runtime = CryptoRuntime(client);
    expect(await runtime.encryptForNotification(notified, 'hi'),
        '${legacyCryptoProviderId} encrypted hi',
        reason: 'the notification was encrypted rather than refused — the '
            'refusal is pqActive\'s, and a capability build that refused '
            'here could not be rolled out ahead of the active one');
    expect(await runtime.encryptForPut(put, 'hi'),
        '${legacyCryptoProviderId} encrypted hi');

    expect(legacy.encryptCalls, 2,
        reason: 'BOTH paths reached the legacy provider — put and notify '
            'alike, which is what the row claims and what asking '
            'providerIdFor twice cannot show');
    expect(pq.encryptCalls, 0,
        reason: 'the control: the post-quantum provider is registered and '
            'resolvable here, so routing legacy is a decision and not the '
            'absence of an alternative');
    expect(notified.metadata.appMetadata?.providerId, legacyCryptoProviderId,
        reason: 'and the notification is STAMPED legacy, so a sibling install '
            'on the previous build reads it by the id it already knows');
    expect(notified.metadata.appMetadata?.providerId,
        put.metadata.appMetadata?.providerId,
        reason: 'the two paths stamp the same thing; a notification an old '
            'install cannot decrypt is as lost as a record it cannot read');
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
    // NOTE: external code reads preference.crypto directly, so the marker has
    // to answer those reads with the published legacy shape.
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

  test('a client never given one falls back to the legacy provider', () {
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

class _Recorder extends CryptoProvider {
  @override
  final String id;
  int encryptCalls = 0;

  _Recorder(this.id);

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    encryptCalls++;
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    atKey.metadata.isEncrypted = true;
    return '$id encrypted $value';
  }

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      '$id decrypted $value';
}
