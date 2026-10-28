import 'package:at_client/at_client.dart';
import 'package:test/test.dart';
import 'test_utils/hive_store.dart';
import 'test_utils/no_keys.dart';

/// Minimal provider — registration is all this test exercises; encrypt/decrypt
/// are never invoked here.
class _StubProvider extends CryptoProvider {
  @override
  final String id;

  _StubProvider(this.id);

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    return 'x';
  }

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      'x';
}

void main() {
  group('crypto-config adoption by a cached client', () {
    AtClientPreference prefWith(String providerId) => AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..crypto = CryptoConfig(
          defaultProviderId: 'legacy', providers: [_StubProvider(providerId)]);

    test(
        'creating the same atSign again with a new provider config adopts it '
        'onto the cached client', () async {
      final atSign = '@cryptoreconcile';
      final storage = hiveStoreAt(atSign, 'test/hive');

      final first = await AtClientImpl.create(
          atSign, 'wavi', prefWith('providerA'),
          atKeysIo: noKeysFor(atSign), storage: storage) as AtClientImpl;
      expect(CryptoConfig.forClient(first).lookup('providerA'), isNotNull,
          reason: 'first create() must adopt the preference provider');

      final again = await AtClientImpl.create(
          atSign, 'wavi', prefWith('providerB'),
          atKeysIo: noKeysFor(atSign), storage: storage);

      expect(identical(again, first), isTrue,
          reason: 'the cached client is handed back, so _init does not run '
              'again to configure the new provider');
      expect(CryptoConfig.forClient(first).lookup('providerB'), isNotNull,
          reason: 'the cached client must adopt the new preference crypto '
              'config, or the next put fails CryptoProviderNotRegistered');

      await first.stop();
    });
  });
}
