import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
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

class FakeDeleteVerbBuilder extends Fake implements DeleteVerbBuilder {}

void main() {
  AtClient mockAtClient = MockAtClientImpl();
  AtLookUp mockAtLookUp = MockAtLookupImpl();
  LocalSecondary mockLocalSecondary = MockLocalSecondary();
  setUp(() {
    reset(mockAtLookUp);
    when(() => mockAtClient.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);

    registerFallbackValue(FakeLocalLookUpVerbBuilder());
    registerFallbackValue(FakeDeleteVerbBuilder());
  });

  test('test to check AtDecryptionException when encrypted value is null',
      () async {
    var selfKeyDecryption = SelfKeyDecryption(mockAtClient);
    var selfKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@alice'
      ..key = 'location';
    expect(
        () async => await selfKeyDecryption.decrypt(selfKey, null),
        throwsA(predicate((e) =>
            e is AtDecryptionException &&
            e.message == 'Decryption failed. Encrypted value is null')));
  });

  test(
      'test to check SelfKeyNotFoundException when self key is not found in local secondary',
      () async {
    var selfKeyDecryption = SelfKeyDecryption(mockAtClient);
    when(() => mockLocalSecondary.getEncryptionSelfKey())
        .thenAnswer((_) => Future.value(null));
    var selfKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@alice'
      ..key = 'location';
    expect(
        () async => await selfKeyDecryption.decrypt(selfKey, 'a@#!!c'),
        throwsA(predicate((e) =>
            e is SelfKeyNotFoundException &&
            e.message == 'Failed to decrypt the key: ${selfKey.toString()} caused by self encryption key not found')));
  });

  test('test to check self encryption key decrypt method without IV', () async {
    SelfKeyDecryption selfKeyDecryption = SelfKeyDecryption(mockAtClient);
    SymmetricKey selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    atChopsKeys.selfEncryptionKey = selfEncryptionKey;

    AtChops atChopsImpl = AtChopsImpl(atChopsKeys);
    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);

    var location = 'san francisco';
    var encryptedLocation =
        EncryptionUtil.encryptValue(location, selfEncryptionKey.key);

    when(() => mockLocalSecondary.getEncryptionSelfKey())
        .thenAnswer((_) => Future.value(selfEncryptionKey.key));
    var selfKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@alice'
      ..key = 'location';
    var decryptedValue =
        await selfKeyDecryption.decrypt(selfKey, encryptedLocation);
    expect(decryptedValue, location);
  });

  test('test to check self encryption key decrypt method with IV', () async {
    SelfKeyDecryption selfKeyDecryption = SelfKeyDecryption(mockAtClient);
    SymmetricKey selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    atChopsKeys.selfEncryptionKey = selfEncryptionKey;

    AtChops atChopsImpl = AtChopsImpl(atChopsKeys);

    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);

    var location = 'new york';
    var ivBase64String = 'YmFzZTY0IGVuY29kaW5n';

    var encryptedLocation = EncryptionUtil.encryptValue(
        location, selfEncryptionKey.key,
        ivBase64: ivBase64String);

    when(() => mockLocalSecondary.getEncryptionSelfKey())
        .thenAnswer((_) => Future.value(selfEncryptionKey.key));
    var selfKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@alice'
      ..key = 'location';
    selfKey.metadata = Metadata()..ivNonce = ivBase64String;
    var decryptedValue =
        await selfKeyDecryption.decrypt(selfKey, encryptedLocation);
    expect(decryptedValue, location);
  });
}
