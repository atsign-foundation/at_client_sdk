import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/legacy/legacy_decryption.dart';
import 'package:at_commons/at_builders.dart';
import 'package:crypton/crypton.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'test_utils/mocks.dart';

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

  test('test to check AtDecryptionException when encrypted value is null',
      () async {
    var sharedKeyDecryption = SharedWithMeDecryption(mockAtClient);
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    expect(
        () async => await sharedKeyDecryption.decrypt(sharedKey, null),
        throwsA(predicate((e) =>
            e is AtDecryptionException &&
            e.message == 'Decryption failed. Encrypted value is null')));
  });

  test('test to check SharedKeyNotFound exception', () async {
    var sharedKeyDecryption = SharedWithMeDecryption(mockAtClient);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
        .thenAnswer((_) => Future.value(null));
    when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) => Future.value('data:null'));
    when(() => mockRemoteSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) => Future.value('data:null'));
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    sharedKey.metadata = (Metadata()..pubKeyCS = 'testCheckSum');
    expect(
        () async => await sharedKeyDecryption.decrypt(sharedKey, 'a@#!!c'),
        throwsA(predicate((e) =>
            e is SharedKeyNotFoundException &&
            e.message == 'shared encryption key not found')));
  });

  test(
      'test to check AtPublicKeyNotFoundException - public key is not found in local secondary',
      () async {
    var sharedKeyDecryption = SharedWithMeDecryption(mockAtClient);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    when(() =>
        mockLocalSecondary.getEncryptionPublicKey(
            '@alice')).thenThrow(AtPublicKeyNotFoundException(
        'Failed to fetch the current atSign public key - public:publickey@alice'));
    when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) => Future.value('data:testEncryptedSharedKey'));
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    sharedKey.metadata = (Metadata()..pubKeyCS = 'testCheckSum');
    expect(
        () async => await sharedKeyDecryption.decrypt(sharedKey, 'a@#!!c'),
        throwsA(predicate((e) =>
            e is AtPublicKeyNotFoundException &&
            e.message ==
                'Failed to fetch the current atSign public key - public:publickey@alice')));
  });

  test(
      'test to check AtPublicKeyChangeException - checksum from metadata is different from checksum of retrieved public key',
      () async {
    var sharedKeyDecryption = SharedWithMeDecryption(mockAtClient);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
        .thenAnswer((_) => Future.value('testPublicKey'));
    when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) => Future.value('data:testEncryptedSharedKey'));
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    sharedKey.metadata = (Metadata()..pubKeyCS = 'testCheckSum');
    expect(
        () async => await sharedKeyDecryption.decrypt(sharedKey, 'a@#!!c'),
        throwsA(predicate((e) =>
            e is AtPublicKeyChangeException &&
            e.message ==
                'Public key has changed. Cannot decrypt shared key @bob:location@alice')));
  });

  test(
      'test to verify that decryption will always use sharedKeyEncrypted if it is present in the metadata',
      () async {
    var sharedKeyDecryption = SharedWithMeDecryption(mockAtClient);
    RSAKeypair aliceKeypair = AtChopsUtil.generateRSAKeyPair(keySize: 2048);
    var aliceEncryptionPublicKey = aliceKeypair.publicKey.toString();
    var aliceEncryptionPrivateKey = aliceKeypair.privateKey.toString();

    var aesSharedKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    var encryptedSharedKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);
    var publicKeyCheckSum =
        EncryptionUtil.md5CheckSum(aliceEncryptionPublicKey);
    var location = 'California';
    var ivBase64String = base64Encode(AtChopsUtil.generateRandomIV(16).ivBytes);
    var encryptedLocation = EncryptionUtil.encryptValue(location, aesSharedKey,
        ivBase64: ivBase64String);
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        aliceEncryptionPublicKey, aliceEncryptionPrivateKey);

    AtChopsKeys atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
    var atChopsImpl = AtChopsImpl(atChopsKeys);
    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
        .thenAnswer((_) => Future.value(aliceEncryptionPublicKey));
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    sharedKey.metadata = (Metadata()
      ..pubKeyCS = publicKeyCheckSum
      ..ivNonce = ivBase64String
      ..sharedKeyEnc = encryptedSharedKey);
    var decryptedLocation =
        await sharedKeyDecryption.decrypt(sharedKey, encryptedLocation);
    expect(decryptedLocation, location);
  });

  test('test to check shared key decryption - with IV', () async {
    var sharedKeyDecryption = SharedWithMeDecryption(mockAtClient);
    RSAKeypair aliceKeypair = AtChopsUtil.generateRSAKeyPair(keySize: 2048);
    var aliceEncryptionPublicKey = aliceKeypair.publicKey.toString();
    var aliceEncryptionPrivateKey = aliceKeypair.privateKey.toString();
    var aesSharedKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256).key;
    var encryptedSharedKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);
    var publicKeyCheckSum =
        EncryptionUtil.md5CheckSum(aliceEncryptionPublicKey);
    var location = 'California';
    var ivBase64String = base64Encode(AtChopsUtil.generateRandomIV(16).ivBytes);
    var encryptedLocation = EncryptionUtil.encryptValue(location, aesSharedKey,
        ivBase64: ivBase64String);
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        aliceEncryptionPublicKey, aliceEncryptionPrivateKey);

    AtChopsKeys atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
    var atChopsImpl = AtChopsImpl(atChopsKeys);
    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);
    when(() => mockAtClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => mockLocalSecondary.getEncryptionPublicKey('@alice'))
        .thenAnswer((_) => Future.value(aliceEncryptionPublicKey));
    when(() => mockLocalSecondary.executeVerb(any<LLookupVerbBuilder>()))
        .thenAnswer((_) => Future.value('data:$encryptedSharedKey'));
    var sharedKey = AtKey()
      ..sharedBy = '@alice'
      ..sharedWith = '@bob'
      ..key = 'location';
    sharedKey.metadata = (Metadata()
      ..pubKeyCS = publicKeyCheckSum
      ..ivNonce = ivBase64String);
    var decryptedLocation =
        await sharedKeyDecryption.decrypt(sharedKey, encryptedLocation);
    expect(decryptedLocation, location);
  });

  test('test to check self key decryption with IV', () async {
    var selfKeyDecryption = SelfKeyDecryption(mockAtClient);
    SymmetricKey selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

    AtChopsKeys atChopsKeys = AtChopsKeys.create(null, null);
    atChopsKeys.selfEncryptionKey = selfEncryptionKey;
    var atChopsImpl = AtChopsImpl(atChopsKeys);

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
