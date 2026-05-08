import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/aes_crypto_scheme.dart';
import 'package:at_client/src/crypto/rsa_crypto_scheme.dart';
import 'package:at_commons/at_commons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'enrollment_service_test.dart';
import 'test_utils/mocks.dart';

void main() {
  MockAtClient mockAtClient = MockAtClient();
  MockAtChops mockAtChops = MockAtChops();
  MockKeyLookup mockKeyLookup = MockKeyLookup();
  MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
  MockLocalSecondary mockLocalSecondary = MockLocalSecondary();
  setUpAll(() {
    when(() => mockAtClient.getLocalSecondary()).thenReturn(mockLocalSecondary);
    when(() => mockAtClient.getRemoteSecondary())
        .thenReturn(mockRemoteSecondary);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    registerFallbackValue(FakeLookupVerbBuilder());
    when(() => mockLocalSecondary.executeVerb(any()))
        .thenAnswer((_) => Future.value('yuh'));
    when(() => mockRemoteSecondary.executeVerb(any()))
        .thenAnswer((_) => Future.value('yuh'));
    when(() => mockLocalSecondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((_) => Future.value('yuh'));
    when(() => mockRemoteSecondary.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((_) => Future.value('yuh'));
    when(() => mockLocalSecondary.getEncryptionPublicKey(any()))
        .thenAnswer((_) => Future.value('some-public-key'));
  });
  group('AES Crypto Scheme', () {
    final plainKey = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
    final aesKey = AESKey(plainKey);
    setUp(() {
      when(() => mockKeyLookup.fetchKey(
            keyName: any(named: 'keyName'),
            sharedWith: any(named: 'sharedWith'),
            sharedBy: any(named: 'sharedBy'),
            algo: any(named: 'algo'),
          )).thenAnswer((_) => Future.value(aesKey));
      when(() => mockAtChops.decryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenAnswer((invocation) {
        var data = invocation.positionalArguments.first;
        return AtEncryptionResult()..result = data.toString().substring(3);
      });
      when(() => mockAtChops.encryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenAnswer((invocation) {
        var data = invocation.positionalArguments.first;
        return AtEncryptionResult()..result = 'abc$data';
      });
      when(() => mockAtClient.atChops).thenReturn(mockAtChops);
    });

    test('✔ encrypt', () async {
      AESScheme scheme = AESScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(await scheme.encrypt(key, value), equals('abcbigdata'));
    });

    test('✘ encrypt -> failed to fetch aesEncryptionKey', () async {
      when(() => mockKeyLookup.fetchKey(
            keyName: any(named: 'keyName'),
            sharedWith: any(named: 'sharedWith'),
            sharedBy: any(named: 'sharedBy'),
            algo: any(named: 'algo'),
          )).thenThrow(KeyNotFoundException('key not found'));
      AESScheme scheme = AESScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(() async => await scheme.encrypt(key, value),
          throwsA(isA<KeyNotFoundException>()));
    });
    test('✘ encrypt -> failed to encrypt', () async {
      when(() => mockAtChops.encryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenThrow(AtEncryptionException('failed'));
      AESScheme scheme = AESScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(() async => await scheme.encrypt(key, value),
          throwsA(isA<AtEncryptionException>()));
    });
    test('✔ decrypt', () async {
      AESScheme scheme = AESScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'abcbigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(await scheme.decrypt(key, value), equals('bigdata'));
    });

    test('✘ decrypt -> failed to fetch aesEncryptionKey', () async {
      when(() => mockKeyLookup.fetchKey(
            keyName: any(named: 'keyName'),
            sharedWith: any(named: 'sharedWith'),
            sharedBy: any(named: 'sharedBy'),
            algo: any(named: 'algo'),
          )).thenThrow(KeyNotFoundException('key not found'));
      AESScheme scheme = AESScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(() async => await scheme.decrypt(key, value),
          throwsA(isA<KeyNotFoundException>()));
    });
    test('✘ decrypt -> failed to decrypt', () async {
      when(() => mockAtChops.decryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenThrow(AtEncryptionException('failed'));
      AESScheme scheme = AESScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(() async => await scheme.decrypt(key, value),
          throwsA(isA<AtEncryptionException>()));
    });
  });

  group('RSA Crypto Scheme', () {
    final plainKey = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
    final aesKey = AESKey(plainKey);
    setUp(() {
      when(() => mockKeyLookup.fetchKey(
            keyName: any(named: 'keyName'),
            sharedWith: any(named: 'sharedWith'),
            sharedBy: any(named: 'sharedBy'),
            algo: any(named: 'algo'),
          )).thenAnswer((_) => Future.value(aesKey));
      when(() => mockAtChops.decryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenAnswer((invocation) {
        var data = invocation.positionalArguments.first;
        return AtEncryptionResult()..result = data.toString().substring(3);
      });
      when(() => mockAtChops.encryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenAnswer((invocation) {
        var data = invocation.positionalArguments.first;
        return AtEncryptionResult()..result = 'abc$data';
      });
      when(() => mockAtChops.encryptString(any(), EncryptionKeyType.rsa2048))
          .thenAnswer(
              (_) => Future.value(AtEncryptionResult()..result = 'encrypted'));
      when(() => mockAtClient.atChops).thenReturn(mockAtChops);
    });

    test('✔ encrypt', () async {
      RSAScheme scheme = RSAScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(await scheme.encrypt(key, value), equals('abcbigdata'));
    });

    test('✔ encrypt -> creates shared key when fetch fails', () async {
      when(() => mockKeyLookup.fetchKey(
            keyName: any(named: 'keyName'),
            sharedWith: any(named: 'sharedWith'),
            sharedBy: any(named: 'sharedBy'),
            algo: any(named: 'algo'),
          )).thenThrow(KeyNotFoundException('key not found'));
      RSAScheme scheme = RSAScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(await scheme.encrypt(key, value), equals('abcbigdata'));
    });

    test('✘ encrypt -> failed to encrypt', () async {
      when(() => mockAtChops.encryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenThrow(AtEncryptionException('failed'));
      RSAScheme scheme = RSAScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'bigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(() async => await scheme.encrypt(key, value),
          throwsA(isA<AtEncryptionException>()));
    });

    test('✔ decrypt', () async {
      RSAScheme scheme = RSAScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'abcbigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(await scheme.decrypt(key, value), equals('bigdata'));
    });

    test('✘ decrypt -> failed to fetch shared key', () async {
      when(() => mockKeyLookup.fetchKey(
            keyName: any(named: 'keyName'),
            sharedWith: any(named: 'sharedWith'),
            sharedBy: any(named: 'sharedBy'),
            algo: any(named: 'algo'),
          )).thenThrow(KeyNotFoundException('key not found'));
      RSAScheme scheme = RSAScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'abcbigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(() async => await scheme.decrypt(key, value),
          throwsA(isA<SharedKeyNotFoundException>()));
    });

    test('✘ decrypt -> failed to decrypt', () async {
      when(() => mockAtChops.decryptString(
            any(),
            EncryptionKeyType.aes256,
            encryptionAlgorithm: any(named: 'encryptionAlgorithm'),
            iv: any(named: 'iv'),
          )).thenThrow(AtDecryptionException('failed'));
      RSAScheme scheme = RSAScheme(
        mockAtClient,
        keyLookup: mockKeyLookup,
      );
      var value = 'abcbigdata';
      AtKey key = AtKey()
        ..key = 'sumkey'
        ..sharedWith = '@bob'
        ..sharedBy = '@alice';
      expect(() async => await scheme.decrypt(key, value),
          throwsA(isA<AtDecryptionException>()));
    });
  });
}
