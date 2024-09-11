import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
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
      'test to verify encryption and decryption of a key shared by @alice with @bob - without IV',
      () async {
    // This test verifies encryption and decryption of a shared key value without using Initialization vector(IV)
    // Value of a shared key is encrypted and then test asserts whether decrypted value is same as original value
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
    // local copy of the AES key that @alice maintains - shared_key.bob@alice
    var sharedKeyEncryptedWithAlicePublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);

    // set atChops for bob
    AtChopsKeys bobAtChopsKeys = AtChopsKeys.create(bobEncryptionKeyPair, null);
    var bobAtChopsImpl = AtChopsImpl(bobAtChopsKeys);
    when(() => bobMockAtClient.atChops).thenAnswer((_) => bobAtChopsImpl);
    when(() => bobMockAtClient.getLocalSecondary())
        .thenAnswer((_) => bobMockLocalSecondary);
    when(() => bobMockAtClient.getCurrentAtSign()).thenReturn('@bob');
    when(() => bobMockLocalSecondary.getEncryptionPublicKey('@bob'))
        .thenAnswer((_) => Future.value(bobEncryptionPublicKey));
    var sharedKeyDecryption = SharedKeyDecryption(bobMockAtClient);

    // encrypted AES key @bob:shared_key@alice
    var sharedKeyEncryptedWithBobPublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, bobEncryptionPublicKey);

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
    sharedKey.metadata = (Metadata()..pubKeyCS = bobPublicKeyCheckSum);
    var encryptionResult =
        await sharedKeyEncryption.encrypt(sharedKey, location);
    expect(encryptionResult != location, true);
    var decryptionResult =
        await sharedKeyDecryption.decrypt(sharedKey, encryptionResult);
    expect(decryptionResult, location);
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
    var sharedKeyDecryption = SharedKeyDecryption(bobMockAtClient);

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
    var ivBase64String = 'YmFzZTY0IGVuY29kaW5n';
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
      'test to verify encryption and decryption of a key shared by @alice with @bob - without IV - local copy of shared AES key is null',
      () async {
    // This test verifies encryption and decryption of a shared key value without using Initialization vector(IV)
    // Local copy shared_key.bob@alice is null. Remote copy shared_key.bob@alice exists in @alice secondary
    // Value of a shared key is encrypted and then test asserts whether decrypted value is same as original value
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

    // remote copy of the AES key from @alice secondary - shared_key.bob@alice
    var sharedKeyEncryptedWithAlicePublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);

    // encrypted AES key @bob:shared_key@alice
    var sharedKeyEncryptedWithBobPublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, bobEncryptionPublicKey);

    // set atChops for bob
    AtChopsKeys bobAtChopsKeys = AtChopsKeys.create(bobEncryptionKeyPair, null);
    var bobAtChopsImpl = AtChopsImpl(bobAtChopsKeys);
    when(() => bobMockAtClient.atChops).thenAnswer((_) => bobAtChopsImpl);
    when(() => bobMockAtClient.getLocalSecondary())
        .thenAnswer((_) => bobMockLocalSecondary);
    when(() => bobMockAtClient.getCurrentAtSign()).thenReturn('@bob');
    when(() => bobMockLocalSecondary.getEncryptionPublicKey('@bob'))
        .thenAnswer((_) => Future.value(bobEncryptionPublicKey));
    var sharedKeyDecryption = SharedKeyDecryption(bobMockAtClient);

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
    when(() =>
        mockLocalSecondary.executeVerb(
            any(that: LLookupLocalSharedKeyMatcher()))).thenAnswer((_) =>
        throw KeyNotFoundException('local key shared_key.bob@alice not found'));
    when(() => mockLocalSecondary.executeVerb(
        any(that: DeleteLocalSharedKeyMatcher()),
        sync: false)).thenAnswer((_) => Future.value('data:1'));
    when(() => mockLocalSecondary.executeVerb(
        any(that: UpdateLocalSharedKeyMatcher()),
        sync: false)).thenAnswer((_) => Future.value('data:2'));
    when(() => mockRemoteSecondary.executeVerb(
            any(that: LLookupLocalSharedKeyMatcher()),
            sync: false))
        .thenAnswer(
            (_) => Future.value('data:$sharedKeyEncryptedWithAlicePublicKey'));
    when(() => mockLocalSecondary
            .executeVerb(any(that: LLookupTheirSharedKeyMatcher())))
        .thenAnswer(
            (_) => Future.value('data:$sharedKeyEncryptedWithBobPublicKey'));
    when(() => mockLocalSecondary
            .executeVerb(any(that: LLookupCachedBobPublicKeyMatcher())))
        .thenAnswer((_) => Future.value('data:$bobEncryptionPublicKey'));
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    sharedKey.metadata = (Metadata()..pubKeyCS = bobPublicKeyCheckSum);
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
