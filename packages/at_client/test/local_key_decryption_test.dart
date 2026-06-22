import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/legacy/legacy_crypto_provider.dart';
import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'test_utils/mocks.dart';

class FakeLocalLookUpVerbBuilder extends Fake implements LLookupVerbBuilder {}

class FakeDeleteVerbBuilder extends Fake implements DeleteVerbBuilder {}

void main() {
  AtClient mockAtClient = MockAtClientImpl();
  AtLookUp mockAtLookUp = MockAtLookUpImpl();
  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
  setUp(() {
    reset(mockAtLookUp);
    when(() => mockAtClient.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);

    registerFallbackValue(FakeLocalLookUpVerbBuilder());
    registerFallbackValue(FakeDeleteVerbBuilder());
  });
  group('A group of local key decryption tests', () {
    test('test to verify decryption of local key', () async {
      var rsaKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
      var sharedSymmetricKey = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
      var encryptedSharedSymmetricKey = EncryptionUtil.encryptKey(
          sharedSymmetricKey, rsaKeyPair.atPublicKey.publicKey);
      AtChopsKeys atChopsKeys = AtChopsKeys.create(rsaKeyPair, null);
      var atChopsImpl = AtChopsImpl(atChopsKeys);
      when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
      when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);
      print('encryptedSharedSymmetricKey:$encryptedSharedSymmetricKey');
      when(() => mockAtClient.getLocalSecondary())
          .thenReturn(mockLocalSecondary);
      when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
          .thenAnswer((_) => Future.value('data:$encryptedSharedSymmetricKey'));
      var localKey = AtKey()
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..key = 'shared_key';
      var testValue = 'abc!@123';
      var encryptedTestValue =
          EncryptionUtil.encryptValue(testValue, sharedSymmetricKey);
      localKey.metadata.appMetadata = AppMetadata(providerId: 'legacy');
      var provider = LegacyCryptoProvider();
      var decryptedTestValue = await provider.decrypt(
          CryptoContext(atClient: mockAtClient), localKey, encryptedTestValue);
      expect(decryptedTestValue, testValue);
    });

    test('test to check AtDecryptionException when encrypted value is null',
        () async {
      when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
      var localKey = AtKey()
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..key = 'shared_key';
      localKey.metadata.appMetadata = AppMetadata(providerId: 'legacy');
      var provider = LegacyCryptoProvider();
      // An empty ciphertext reaches the same null/empty guard as the old
      // nullable-ciphertext request did; decrypt() now takes a non-null String.
      expect(
          () async => await provider.decrypt(
              CryptoContext(atClient: mockAtClient), localKey, ''),
          throwsA(predicate((e) =>
              e is AtDecryptionException &&
              e.message == 'Decryption failed. Encrypted value is null')));
    });

    test(
        'test to check SharedKeyNotFoundException when shared key is empty/null',
        () async {
      var sharedSymmetricKey = 'REqkIcl9HPekt0T7+rZhkrBvpysaPOeC2QL1PVuWlus=';
      when(() => mockAtClient.getLocalSecondary())
          .thenReturn(mockLocalSecondary);
      when(() => mockAtClient.getRemoteSecondary())
          .thenReturn(mockRemoteSecondary);
      when(() => mockLocalSecondary.executeVerb(any<DeleteVerbBuilder>(),
          sync: false)).thenAnswer((_) => Future.value('data:-1'));
      when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
          .thenAnswer((_) => Future.value('data:null'));
      when(() => mockRemoteSecondary.executeVerb(any<LLookupVerbBuilder>()))
          .thenAnswer((_) => Future.value('data:null'));

      var localKey = AtKey()
        ..sharedBy = '@alice'
        ..sharedWith = '@bob'
        ..key = 'shared_key';
      var testValue = 'abc!@123';
      var encryptedTestValue =
          EncryptionUtil.encryptValue(testValue, sharedSymmetricKey);
      localKey.metadata.appMetadata = AppMetadata(providerId: 'legacy');
      var provider = LegacyCryptoProvider();
      expect(
          () async => await provider.decrypt(
              CryptoContext(atClient: mockAtClient),
              localKey,
              encryptedTestValue),
          throwsA(predicate((e) =>
              e is SharedKeyNotFoundException &&
              e.message == 'Empty or null SharedKey is found')));
    });
  });
}
