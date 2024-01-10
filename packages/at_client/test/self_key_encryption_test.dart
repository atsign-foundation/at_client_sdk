import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/encryption_service/self_key_encryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';

class MockAtClientImpl extends Mock implements AtClient {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookupImpl extends Mock implements AtLookUp {}

class FakeLocalLookUpVerbBuilder extends Fake implements LLookupVerbBuilder {}

void main() {
  AtClient mockAtClient = MockAtClientImpl();
  AtLookUp mockAtLookUp = MockAtLookupImpl();
  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
  setUp(() {
    reset(mockAtLookUp);
    when(() => mockAtClient.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);
    when(() => mockAtClient.getRemoteSecondary())
        .thenAnswer((_) => mockRemoteSecondary);

    registerFallbackValue(FakeLocalLookUpVerbBuilder());
  });

  test('test to check encryption/decryption of self keys', () async {
    // This test encrypts a self key value and then checks whether decrypted value is same as original value
    // If @alice wants to maintain a location without sharing to anyone then the key-value format will be @alice:location@alice New Jersey
    // @alice uses self encryption AES key generated during onboarding process to encrypt the value. Same key is used for decryption
    var selfKeyEncryption = SelfKeyEncryption(mockAtClient);
    var selfKeyDecryption = SelfKeyDecryption(mockAtClient);
    // generate new AES key for the test
    var aliceSelfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    // set atChops
    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    atChopsKeys.selfEncryptionKey = AESKey(aliceSelfEncryptionKey);
    var atChopsImpl = AtChopsImpl(atChopsKeys);
    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);
    when(() => mockLocalSecondary.getEncryptionSelfKey())
        .thenAnswer((_) => Future.value(aliceSelfEncryptionKey));
    var selfKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    var location = 'New Jersey';
    var encryptedValue = await selfKeyEncryption.encrypt(selfKey, location);
    expect(encryptedValue != location, true);
    var decryptionResult =
        await selfKeyDecryption.decrypt(selfKey, encryptedValue);
    expect(decryptionResult, location);
  });
  test(
      'test to check self key encryption throws exception when passed value is not string type',
      () async {
    var selfKeyEncryption = SelfKeyEncryption(mockAtClient);
    var selfKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    var locations = ['new jersey', 'new york'];
    expect(
        () async => await selfKeyEncryption.encrypt(selfKey, locations),
        throwsA(predicate((dynamic e) =>
            e is AtEncryptionException &&
            e.message ==
                'Invalid value type found: List<String>. Valid value type is String')));
  });
}
