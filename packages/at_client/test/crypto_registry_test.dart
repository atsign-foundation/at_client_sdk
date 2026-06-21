import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

class _FakeCryptoProvider extends CryptoProvider {
  @override
  final String id;

  _FakeCryptoProvider(this.id);

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    return value;
  }

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(providerId: id);
    return value;
  }
}

void main() {
  group('CryptoRegistry', () {
    test('register adds provider and can lookup by id', () async {
      final registry = CryptoRegistry();
      final provider = _FakeCryptoProvider('provider-a');

      registry.register(provider);

      expect(registry.contains('provider-a'), isTrue);
      expect(registry.registeredProviderIds, contains('provider-a'));
      expect(registry.lookup('provider-a'), same(provider));
    });

    test('lookup throws CryptoProviderNotRegistered for unknown id', () {
      final registry = CryptoRegistry();
      registry.register(_FakeCryptoProvider('provider-a'));

      expect(
        () => registry.lookup('missing-provider', lookupReason: 'put'),
        throwsA(
          isA<CryptoProviderNotRegistered>()
              .having(
                (e) => e.message,
                'message',
                contains('missing-provider'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('provider-a'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('Lookup reason: put'),
              ),
        ),
      );
    });

    test('contains returns false for unknown ids', () {
      final registry = CryptoRegistry();

      expect(registry.contains('missing-provider'), isFalse);
    });

    test('registeredProviderIds is empty initially', () {
      final registry = CryptoRegistry();

      expect(registry.registeredProviderIds, isEmpty);
    });

    test('registering existing id throws by default', () async {
      final registry = CryptoRegistry();
      final first = _FakeCryptoProvider('same-id');
      final second = _FakeCryptoProvider('same-id');

      registry.register(first);

      expect(
        () => registry.register(second),
        throwsA(isA<ArgumentError>()),
      );
      expect(registry.lookup('same-id'), same(first));
    });

    test('registering existing id can replace when explicit', () async {
      final registry = CryptoRegistry();
      final first = _FakeCryptoProvider('same-id');
      final second = _FakeCryptoProvider('same-id');

      registry.register(first);
      registry.register(second, replace: true);

      expect(registry.lookup('same-id'), same(second));
      expect(
        registry.registeredProviderIds.where((e) => e == 'same-id').length,
        1,
      );
    });

    test('config stores its default provider id and provider instances', () {
      final provider = _FakeCryptoProvider('provider-a');

      final config = CryptoConfig(
        defaultProviderId: 'provider-a',
        providers: [provider],
      );

      expect(config.defaultProviderId, 'provider-a');
      expect(config.providers, [provider]);
    });

    test('registeredProviderIds is not growable', () {
      final registry = CryptoRegistry();
      registry.register(_FakeCryptoProvider('provider-a'));
      final providerIds = registry.registeredProviderIds;

      expect(() => providerIds.add('newName'), throwsUnsupportedError);
    });
  });
}
