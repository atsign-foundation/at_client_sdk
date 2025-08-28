import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/decryption_service/shared_with_me_decryption.dart';
import 'package:at_client/src/encryption_service/shared_key_encryption.dart';
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
  RemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
  setUp(() {
    reset(mockAtLookUp);
    when(() => mockAtClient.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);
    when(() => mockAtClient.getRemoteSecondary())
        .thenAnswer((_) => mockRemoteSecondary);

    registerFallbackValue(FakeLocalLookUpVerbBuilder());
    registerFallbackValue(FakeDeleteVerbBuilder());
  });

  test(
      'test to verify encryption and decryption of a key shared by @alice with @bob - with IV',
      () async {
    // This test verifies encryption and decryption of a shared key value by using Initialization vector(IV)
    // If @alice wants to share location value with bob, then key-value format is @bob:location@alice California
    // @alice will generate a AES key and will encrypt the location value - California
    // The  AES key will be encrypted with @bob's public key and stored in @bob:shared_key@alice
    // When @bob wants to decrypt the @alice's location, @bob will read the encrypted  AES key from @bob:shared_key@alice
    // @bob will decrypt the AES key using @bob's private key
    // @bob will decrypt the location value - California with AES key

    var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
    var bobMockAtClient = MockAtClientImpl();
    var bobMockLocalSecondary = MockLocalSecondary();
    // set up encryption key pair for @alice. This will be used during encryption process
    var aliceEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    var aliceEncryptionPublicKey = aliceEncryptionKeyPair.atPublicKey.publicKey;
    // Set up encryption key pair for @bob. This will be used during decryption process
    var bobEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    var bobEncryptionPublicKey = bobEncryptionKeyPair.atPublicKey.publicKey;

    // Generate the AES for encrypting the location value
    var aesSharedKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    // set atChops for bob
    AtChopsKeys bobAtChopsKeys = AtChopsKeys.create(bobEncryptionKeyPair, null);
    var bobAtChopsImpl = AtChopsImpl(bobAtChopsKeys);
    when(() => bobMockAtClient.atChops).thenAnswer((_) => bobAtChopsImpl);
    when(() => bobMockAtClient.getLocalSecondary())
        .thenAnswer((_) => bobMockLocalSecondary);
    when(() => bobMockAtClient.getCurrentAtSign()).thenReturn('@bob');
    when(() => bobMockLocalSecondary.getEncryptionPublicKey('@bob'))
        .thenAnswer((_) => Future.value(bobEncryptionPublicKey));
    var sharedKeyDecryption = SharedWithMeDecryption(bobMockAtClient);

    // encrypted AES key @bob:shared_key@alice
    var sharedKeyEncryptedWithBobPublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, bobEncryptionPublicKey);

    // local copy of the AES key that @alice maintains - shared_key.bob@alice
    var sharedKeyEncryptedWithAlicePublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);

    var bobPublicKeyCheckSum =
        EncryptionUtil.md5CheckSum(bobEncryptionPublicKey);
    var location = 'California';

    // set atChops for alice
    AtChopsKeys atChopsKeys = AtChopsKeys.create(aliceEncryptionKeyPair, null);
    var atChopsImpl = AtChopsImpl(atChopsKeys);
    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
        .thenAnswer((_) => Future.value(aliceEncryptionPublicKey));
    when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((Invocation invocation) {
      final builder = invocation.positionalArguments[0] as LLookupVerbBuilder;
      final buildKeyValue = builder.buildKey();
      if (buildKeyValue == 'shared_key.bob@alice') {
        return Future.value('data:$sharedKeyEncryptedWithAlicePublicKey');
      } else if (buildKeyValue == 'cached:public:publickey@bob') {
        return Future.value('data:$bobEncryptionPublicKey');
      } else if (buildKeyValue == '@bob:shared_key@alice') {
        return Future.value('data:$sharedKeyEncryptedWithBobPublicKey');
      } else {
        return Future.value('data:null');
      }
    });
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    // random IV string
    var ivBase64String = EncryptionUtil.generateIV();
    sharedKey.metadata = Metadata()
      ..pubKeyCS = bobPublicKeyCheckSum
      ..ivNonce = ivBase64String;
    var encryptionResult =
        await sharedKeyEncryption.encrypt(sharedKey, location);
    expect(encryptionResult != location, true);
    var decryptionResult =
        await sharedKeyDecryption.decrypt(sharedKey, encryptionResult);
    expect(decryptionResult, location);
  });

  test('Verify we will always set the correct encrypted shared key in metadata',
      () async {
    // Variant on the previous test. This time we're going to deliberately
    // return a bogus value when the sender looks up their copy of the
    // shared key encrypted for the recipient.

    var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
    var bobMockAtClient = MockAtClientImpl();
    var bobMockLocalSecondary = MockLocalSecondary();
    // set up encryption key pair for @alice. This will be used during encryption process
    var aliceEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    var aliceEncryptionPublicKey = aliceEncryptionKeyPair.atPublicKey.publicKey;
    // Set up encryption key pair for @bob. This will be used during decryption process
    var bobEncryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    var bobEncryptionPublicKey = bobEncryptionKeyPair.atPublicKey.publicKey;

    // Generate the AES for encrypting the location value
    var actualSymmetricKeyBeingUsed =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    var aDifferentSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    // set atChops for bob
    AtChopsKeys bobAtChopsKeys = AtChopsKeys.create(bobEncryptionKeyPair, null);
    var bobAtChopsImpl = AtChopsImpl(bobAtChopsKeys);
    when(() => bobMockAtClient.atChops).thenAnswer((_) => bobAtChopsImpl);
    when(() => bobMockAtClient.getLocalSecondary())
        .thenAnswer((_) => bobMockLocalSecondary);
    when(() => bobMockAtClient.getCurrentAtSign()).thenReturn('@bob');
    when(() => bobMockLocalSecondary.getEncryptionPublicKey('@bob'))
        .thenAnswer((_) => Future.value(bobEncryptionPublicKey));
    var sharedKeyDecryption = SharedWithMeDecryption(bobMockAtClient);

    // local copy of the AES key that @alice maintains - shared_key.bob@alice
    var symmetricKeyEncryptedWithAlicePublicKey = EncryptionUtil.encryptKey(
        actualSymmetricKeyBeingUsed, aliceEncryptionPublicKey);

    // a DIFFERENT AES key encrypted with bob's public key @bob:shared_key@alice
    var differentSharedKeyEncryptedWithBobPublicKey = EncryptionUtil.encryptKey(
        aDifferentSymmetricKey, bobEncryptionPublicKey);

    var bobPublicKeyCheckSum =
        EncryptionUtil.md5CheckSum(bobEncryptionPublicKey);
    var location = 'California';

    // set atChops for alice
    AtChopsKeys atChopsKeys = AtChopsKeys.create(aliceEncryptionKeyPair, null);
    var atChopsImpl = AtChopsImpl(atChopsKeys);
    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
        .thenAnswer((_) => Future.value(aliceEncryptionPublicKey));
    when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((Invocation invocation) {
      final builder = invocation.positionalArguments[0] as LLookupVerbBuilder;
      final buildKeyValue = builder.buildKey();
      if (buildKeyValue == 'shared_key.bob@alice') {
        // This is alice's copy of the symmetric key
        return Future.value('data:$symmetricKeyEncryptedWithAlicePublicKey');
      } else if (buildKeyValue == 'cached:public:publickey@bob') {
        return Future.value('data:$bobEncryptionPublicKey');
      } else if (buildKeyValue == '@bob:shared_key@alice') {
        // this is alice's datastore copy of the symmetric key encrypted
        // with bob's public key. We're going to return a bogus value here
        // because we want to verify that this value is now always ignored
        // in order to eliminate the race condition identified in
        // https://github.com/atsign-foundation/at_client_sdk/issues/1506
        return Future.value(
            'data:$differentSharedKeyEncryptedWithBobPublicKey');
      } else {
        return Future.value('data:null');
      }
    });
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    // random IV string
    var ivBase64String = EncryptionUtil.generateIV();
    sharedKey.metadata = Metadata()
      ..pubKeyCS = bobPublicKeyCheckSum
      ..ivNonce = ivBase64String;
    var encryptionResult =
        await sharedKeyEncryption.encrypt(sharedKey, location);
    expect(encryptionResult != location, true);
    var decryptionResult =
        await sharedKeyDecryption.decrypt(sharedKey, encryptionResult);
    expect(decryptionResult, location);
  });

  test(
      'test to check shared key encryption throws exception when passed value is not string type',
      () async {
    var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
    var selfKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    var locations = ['new jersey', 'new york'];
    expect(
        () async => await sharedKeyEncryption.encrypt(selfKey, locations),
        throwsA(predicate((dynamic e) =>
            e is AtEncryptionException &&
            e.message ==
                'Invalid value type found: List<String>. Valid value type is String')));
  });
}

class LLookupLocalSharedKeyMatcher extends Matcher {
  @override
  Description describe(Description description) => description
      .add('A custom matcher to match LOOKUPS of encrypted shared key');

  @override
  bool matches(item, Map matchState) {
    if (item is LLookupVerbBuilder && item.atKey.key == 'shared_key.bob') {
      return true;
    }
    return false;
  }
}

class LLookupCachedBobPublicKeyMatcher extends Matcher {
  @override
  Description describe(Description description) => description
      .add('A custom matcher to match LOOKUPS of encrypted shared key');

  @override
  bool matches(item, Map matchState) {
    if (item is LLookupVerbBuilder &&
        item.atKey.key == 'publickey' &&
        item.atKey.sharedBy == '@bob' &&
        item.atKey.metadata.isPublic == true) {
      return true;
    }
    return false;
  }
}

class LLookupTheirSharedKeyMatcher extends Matcher {
  @override
  Description describe(Description description) => description
      .add('A custom matcher to match LOOKUPS of encrypted shared key');

  @override
  bool matches(item, Map matchState) {
    if (item is LLookupVerbBuilder &&
        item.atKey.key == 'shared_key' &&
        item.atKey.sharedWith == '@bob' &&
        item.atKey.sharedBy == '@alice') {
      return true;
    }
    return false;
  }
}

class UpdateLocalSharedKeyMatcher extends Matcher {
  @override
  Description describe(Description description) => description
      .add('A custom matcher to match UPDATE of encrypted shared key');

  @override
  bool matches(item, Map matchState) {
    if (item is UpdateVerbBuilder && item.atKey.key == 'shared_key.bob') {
      return true;
    }
    return false;
  }
}

class DeleteLocalSharedKeyMatcher extends Matcher {
  @override
  Description describe(Description description) => description
      .add('A custom matcher to match Deletes of encrypted shared key');

  @override
  bool matches(item, Map matchState) {
    if (item is DeleteVerbBuilder &&
        item.atKey.key == 'shared_key' &&
        item.atKey.sharedWith == '@bob' &&
        item.atKey.sharedBy == '@alice') {
      return true;
    }
    return false;
  }
}
