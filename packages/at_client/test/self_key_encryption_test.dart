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

  test('test to check self key encryption', () async {
    var selfKeyEncryption = SelfKeyEncryption(mockAtClient);
    var selfKeyDecryption = SelfKeyDecryption(mockAtClient);
    var aliceSelfEncryptionKey = 'vR+w/lx9qitj/W2+SfFxbjeRM8VdaYGsxG6lxYCVQ0w=';
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
