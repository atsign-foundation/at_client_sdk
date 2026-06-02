import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  group('CryptoRuntime', () {
    late MockAtClient mockAtClient;
    late MockAtChops mockAtChops;
    late CryptoRegistry registry;
    late _RecordingProvider legacyProvider;
    late _RecordingProvider customProvider;

    setUp(() {
      mockAtClient = MockAtClient();
      mockAtChops = MockAtChops();
      registry = CryptoRegistry();
      legacyProvider = _RecordingProvider('legacy');
      customProvider = _RecordingProvider('custom');

      registry.register(legacyProvider);
      registry.register(customProvider);
      when(() => mockAtClient.atChops).thenReturn(mockAtChops);
      when(() => mockAtClient.cryptoRegistry).thenReturn(registry);
    });

    test('uses legacy provider when appMetadata is absent', () async {
      final atKey = AtKey()..metadata = Metadata();

      final result =
          await CryptoRuntime(mockAtClient).encryptForPut(atKey, 'data');

      expect(result.ciphertext, 'legacy encrypted data');
      expect(result.metadata.providerId, 'legacy');
      expect(result.isEncrypted, true);
      expect(legacyProvider.encryptCalls, 1);
      expect(customProvider.encryptCalls, 0);
    });

    test('routes decryption by stored appMetadata providerId', () async {
      final atKey = AtKey()
        ..metadata =
            (Metadata()..appMetadata = AppMetadata(providerId: 'custom'));

      final decrypted =
          await CryptoRuntime(mockAtClient).decryptForGet(atKey, 'ciphertext');

      expect(decrypted, 'custom decrypted ciphertext');
      expect(legacyProvider.decryptCalls, 0);
      expect(customProvider.decryptCalls, 1);
    });

    test('preserves provider-owned additional metadata', () async {
      final provider = _MetadataProvider();
      registry.register(provider);
      final atKey = AtKey()
        ..metadata = (Metadata()
          ..appMetadata = AppMetadata(providerId: 'metadata-provider'));

      final result =
          await CryptoRuntime(mockAtClient).encryptForPut(atKey, 'plaintext');

      expect(result.ciphertext, 'ciphertext');
      expect(result.metadata.additional, {
        'sessionId': 'session-1',
        'epoch': 7,
      });
      expect(atKey.metadata.appMetadata?.additional, {
        'sessionId': 'session-1',
        'epoch': 7,
      });

      final plaintext = await CryptoRuntime(mockAtClient)
          .decryptForGet(atKey, result.ciphertext);

      expect(plaintext, 'plaintext');
      expect(provider.decryptMetadata?.additional, {
        'sessionId': 'session-1',
        'epoch': 7,
      });
    });

    test('policy registers a missing provider and retry uses it', () async {
      final policy = _RegisteringPolicy(_MetadataProvider());
      final lazyAtClient = MockAtClientImpl();
      final lazyAtChops = MockAtChops();
      final lazyRegistry = _CountingRegistry();
      when(() => lazyAtClient.atChops).thenReturn(lazyAtChops);
      when(() => lazyAtClient.cryptoRegistry).thenReturn(lazyRegistry);
      when(() => lazyAtClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => lazyAtClient.getPreferences()).thenReturn(
        AtClientPreference()
          ..crypto = CryptoConfig(
            defaultProviderId: 'legacy',
            policy: policy,
          ),
      );
      final atKey = AtKey()
        ..metadata = (Metadata()
          ..appMetadata = AppMetadata(providerId: 'metadata-provider'));

      final plaintext =
          await CryptoRuntime(lazyAtClient).decryptForGet(atKey, 'ciphertext');

      expect(plaintext, 'plaintext');
      expect(policy.calls, 1);
      expect(lazyRegistry.contains('metadata-provider'), true);
      expect(lazyRegistry.lookupIds, [
        'metadata-provider',
        'metadata-provider',
      ]);
    });

    test('policy retry happens once when provider remains missing', () async {
      final policy = _RetryOnlyPolicy();
      final lazyAtClient = MockAtClientImpl();
      final lazyAtChops = MockAtChops();
      final lazyRegistry = _CountingRegistry();
      when(() => lazyAtClient.atChops).thenReturn(lazyAtChops);
      when(() => lazyAtClient.cryptoRegistry).thenReturn(lazyRegistry);
      when(() => lazyAtClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => lazyAtClient.getPreferences()).thenReturn(
        AtClientPreference()
          ..crypto = CryptoConfig(
            defaultProviderId: 'legacy',
            policy: policy,
          ),
      );
      final atKey = AtKey()
        ..metadata = (Metadata()
          ..appMetadata = AppMetadata(providerId: 'missing-provider'));

      await expectLater(
        () => CryptoRuntime(lazyAtClient).decryptForGet(atKey, 'ciphertext'),
        throwsA(isA<CryptoProviderNotRegistered>()),
      );
      expect(policy.calls, 1);
      expect(lazyRegistry.lookupIds, [
        'missing-provider',
        'missing-provider',
      ]);
    });
  });
}

class _CountingRegistry extends CryptoRegistry {
  final lookupIds = <String>[];

  @override
  CryptoProvider lookup(String id, {String? operation}) {
    lookupIds.add(id);
    return super.lookup(id, operation: operation);
  }
}

class _RecordingProvider extends CryptoProvider {
  @override
  final String id;
  int encryptCalls = 0;
  int decryptCalls = 0;

  _RecordingProvider(this.id);

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    encryptCalls++;
    return CryptoEncryptResult(
      ciphertext: '$id encrypted ${request.plaintext}',
      metadata: AppMetadata(providerId: id),
    );
  }

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    decryptCalls++;
    return CryptoDecryptResult(
      plaintext: '$id decrypted ${request.ciphertext}',
    );
  }
}

class _MetadataProvider extends CryptoProvider {
  AppMetadata? decryptMetadata;

  @override
  String get id => 'metadata-provider';

  @override
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    return CryptoEncryptResult(
      ciphertext: 'ciphertext',
      metadata: AppMetadata(
        providerId: 'metadata-provider',
        additional: {
          'sessionId': 'session-1',
          'epoch': 7,
        },
      ),
    );
  }

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    decryptMetadata = request.metadata;
    return const CryptoDecryptResult(plaintext: 'plaintext');
  }
}

class _RegisteringPolicy extends CryptoPolicy {
  final CryptoProvider provider;
  int calls = 0;

  _RegisteringPolicy(this.provider);

  @override
  Future<CryptoFailureResolution> onProviderNotFound(
    CryptoProviderNotFoundContext context,
  ) async {
    calls++;
    await context.registerProvider(provider);
    return const CryptoFailureResolution.retry();
  }
}

class _RetryOnlyPolicy extends CryptoPolicy {
  int calls = 0;

  @override
  CryptoFailureResolution onProviderNotFound(
    CryptoProviderNotFoundContext context,
  ) {
    calls++;
    return const CryptoFailureResolution.retry();
  }
}
