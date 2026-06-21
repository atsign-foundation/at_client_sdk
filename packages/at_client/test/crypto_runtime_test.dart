import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  group('CryptoRuntime', () {
    late MockAtClient mockAtClient;
    late MockAtChops mockAtChops;
    late _RecordingProvider legacyProvider;
    late _RecordingProvider customProvider;

    // Point the client's preference at a CryptoConfig holding [providers];
    // CryptoRuntime resolves against preference.crypto (no separate registry).
    void configure(List<CryptoProvider> providers,
        {String defaultId = 'legacy'}) {
      mockAtClient.getPreferences().crypto =
          CryptoConfig(defaultProviderId: defaultId, providers: providers);
    }

    setUp(() {
      mockAtClient = MockAtClient();
      mockAtChops = MockAtChops();
      legacyProvider = _RecordingProvider('legacy');
      customProvider = _RecordingProvider('custom');
      when(() => mockAtClient.atChops).thenReturn(mockAtChops);
      configure([legacyProvider, customProvider]);
    });

    test('uses legacy provider when appMetadata is absent', () async {
      final atKey = AtKey()..metadata = Metadata();

      final ciphertext =
          await CryptoRuntime(mockAtClient).encryptForPut(atKey, 'data');

      expect(ciphertext, 'legacy encrypted data');
      // The runtime stamps providerId + isEncrypted after the provider returns.
      expect(atKey.metadata.appMetadata?.providerId, 'legacy');
      expect(atKey.metadata.isEncrypted, true);
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
      configure([provider]);
      final atKey = AtKey()
        ..metadata = (Metadata()
          ..appMetadata = AppMetadata(providerId: 'metadata-provider'));

      final ciphertext =
          await CryptoRuntime(mockAtClient).encryptForPut(atKey, 'plaintext');

      expect(ciphertext, 'ciphertext');
      // The provider's appMetadata.additional survives the runtime's re-stamp.
      expect(atKey.metadata.appMetadata?.additional, {
        'sessionId': 'session-1',
        'epoch': 7,
      });

      final plaintext =
          await CryptoRuntime(mockAtClient).decryptForGet(atKey, ciphertext);

      expect(plaintext, 'plaintext');
      expect(provider.decryptMetadata?.additional, {
        'sessionId': 'session-1',
        'epoch': 7,
      });
    });

    test('throws when the routed provider is not registered', () async {
      final atKey = AtKey()
        ..metadata = (Metadata()
          ..appMetadata = AppMetadata(providerId: 'missing-provider'));

      await expectLater(
        () => CryptoRuntime(mockAtClient).decryptForGet(atKey, 'ciphertext'),
        throwsA(isA<CryptoProviderNotRegistered>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('missing-provider'),
            contains('Lookup reason: get'),
            contains('custom'),
          ),
        )),
      );
      expect(legacyProvider.decryptCalls, 0);
      expect(customProvider.decryptCalls, 0);
    });

    test('rejects a non-String plaintext before reaching the provider',
        () async {
      final atKey = AtKey()..metadata = Metadata();

      await expectLater(
        () => CryptoRuntime(mockAtClient).encryptForPut(atKey, 918078908676),
        throwsA(isA<AtEncryptionException>().having(
          (e) => e.message,
          'message',
          'Invalid value type found: int. Valid value type is String',
        )),
      );
      // The guard fires at the runtime boundary; no provider runs.
      expect(legacyProvider.encryptCalls, 0);
    });

    test('passes a null ciphertext to the provider as empty string', () async {
      final atKey = AtKey()..metadata = Metadata();

      // A null ciphertext must not blow up with a cast TypeError; it reaches
      // the provider as '' so the provider surfaces its own null-value error.
      final decrypted =
          await CryptoRuntime(mockAtClient).decryptForGet(atKey, null);

      expect(decrypted, 'legacy decrypted ');
      expect(legacyProvider.decryptCalls, 1);
    });

    test('stamps providerId and isEncrypted even when the provider does not',
        () async {
      configure([_BareProvider()]);
      final atKey = AtKey()
        ..metadata =
            (Metadata()..appMetadata = AppMetadata(providerId: 'bare'));

      final ciphertext =
          await CryptoRuntime(mockAtClient).encryptForPut(atKey, 'data');

      expect(ciphertext, 'bare:data');
      // _BareProvider touches no metadata; the runtime stamps it so a forgetful
      // provider can't silently leave isEncrypted false (= undecrypted reads).
      expect(atKey.metadata.appMetadata?.providerId, 'bare');
      expect(atKey.metadata.isEncrypted, true);
    });
  });
}

class _RecordingProvider extends CryptoProvider {
  @override
  final String id;
  int encryptCalls = 0;
  int decryptCalls = 0;

  _RecordingProvider(this.id);

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
      CryptoContext context, AtKey atKey, String value) async {
    decryptCalls++;
    return '$id decrypted $value';
  }
}

class _MetadataProvider extends CryptoProvider {
  AppMetadata? decryptMetadata;

  @override
  String get id => 'metadata-provider';

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String value) async {
    atKey.metadata.appMetadata = AppMetadata(
      providerId: 'metadata-provider',
      additional: {
        'sessionId': 'session-1',
        'epoch': 7,
      },
    );
    atKey.metadata.isEncrypted = true;
    return 'ciphertext';
  }

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String value) async {
    decryptMetadata = atKey.metadata.appMetadata;
    return 'plaintext';
  }
}

/// Returns ciphertext but deliberately touches no metadata, to prove the
/// runtime stamps providerId + isEncrypted on the provider's behalf.
class _BareProvider extends CryptoProvider {
  @override
  String get id => 'bare';

  @override
  Future<String> encrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      'bare:$value';

  @override
  Future<String> decrypt(
          CryptoContext context, AtKey atKey, String value) async =>
      value;
}
