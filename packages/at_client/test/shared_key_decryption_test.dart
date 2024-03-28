import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/decryption_service/self_key_decryption.dart';
import 'package:at_client/src/decryption_service/shared_key_decryption.dart';
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

  test('test to check AtDecryptionException when encrypted value is null',
      () async {
    var sharedKeyDecryption = SharedKeyDecryption(mockAtClient);
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
    var sharedKeyDecryption = SharedKeyDecryption(mockAtClient);
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
    var sharedKeyDecryption = SharedKeyDecryption(mockAtClient);
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
    var sharedKeyDecryption = SharedKeyDecryption(mockAtClient);
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

  test('test to check shared key decryption - without IV', () async {
    var sharedKeyDecryption = SharedKeyDecryption(mockAtClient);
    var aliceEncryptionPublicKey =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0sYjWt6TTikajY3HjvdN3sn2Ve3O+i84/gBrWPqhGNSdImz3W2l9dMSHm4wyixsxMSQaL+rECjwnvp3sRdW3M51sDCvWa06MLptvdrtnMjzDrvP45hUJY/i6WeDW8qeEOf9zuo+BLcQ3pkV1KZyhBj80OndLS/y00T8fYB9KnS5Z/iN7KW7Hxuv0isMPXxL1i8AZos7m5GuWq7CfRFKJIZ6vqYBUJCVSQCUVo1llyjElodSywcf1KjCvBOKuMPnUQCs+pKJt3QMFI0U7D+yinnlEdr6TBfOzMMPS3Du1LHpTGt7rqyxZrX8p4kpVb/CyL6wkelMuahHDOeNFBNyF0wIDAQAB';
    var aliceEncryptionPrivateKey =
        'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDSxiNa3pNOKRqNjceO903eyfZV7c76Lzj+AGtY+qEY1J0ibPdbaX10xIebjDKLGzExJBov6sQKPCe+nexF1bcznWwMK9ZrTowum292u2cyPMOu8/jmFQlj+LpZ4Nbyp4Q5/3O6j4EtxDemRXUpnKEGPzQ6d0tL/LTRPx9gH0qdLln+I3spbsfG6/SKww9fEvWLwBmizubka5arsJ9EUokhnq+pgFQkJVJAJRWjWWXKMSWh1LLBx/UqMK8E4q4w+dRAKz6kom3dAwUjRTsP7KKeeUR2vpMF87Mww9LcO7UselMa3uurLFmtfyniSlVv8LIvrCR6Uy5qEcM540UE3IXTAgMBAAECggEAfImMLE3k1cLdqJQEPIoNHb1RatZXfGXYk+QliW6VLzm5GrUttnpvIUZaJeNBngXUHAgL3RInATEn/q4LA/xSAhJa3Bou2DqSA5vd0VbLk9hpev82qqP1Z3d4jFCYUMoAC9DPTYUrO6J7iyfxIUQltK41qvH/sIdBQ327iS0UBihhiKg16BOKG4SoFJHZfhhL6m86+jnsaBTaAWb8hpa/Mwqs5eDHF78DHK8o+4Q6DufDi34nCwdxEexL3MFa9L0qGbQAqJshgDcJ6yxUzb5+tw3XXpiE0yG9aZ5gPaS2UgOYY1m2mmF4RjFSiLmKyN99H99ycA59enVFyfYh4SnuMQKBgQDq9IwkVyDkNxkaW6hyYMzBwNqId74JUNjXCWyzDJ58JWaNvFYYY4ujSCLTdfdugmVTIUjqXMVsxzq/e9jNaOj7u27/3inqn1VC88GFJJiUiLQcTP1T5ySP4jy5GVrhQ1zP8PtiRqE34emYfVY8OLa7bwf5CufgbL5RzKPrfIafKQKBgQDlpx8DoETRPE7FyZJg9xiUTyZmI/P6RmhCO86knbQa4hEWiCuEIiOheJQxdcW6yCNImbJNSEFUnpweiHEw4xdMmlpR4JDkvsGOyjLI6Y36Yxbi+AipvTuYZ/La7fuOeEjwD7OlgJmva2jEQL6GlhmTibgt5dfwzOiAP0gC4tXomwKBgQDAnZDSLfeSADV9LU0vz3mtEYxWOkw52OSbjWdmdd7ricHESnUOc3VDe9zJHLmnCBFHEE91im5zWfUoi8BVzT7LOIKsEpaseMjuJWUt4K2Rf2ygkuFPSnvn1SHQ4R9m8tGAy19a1upOJM9bKs1qe1ga2tBfc3havOtdpfVwFVtL2QKBgDFsPehx3V2KNQmrz6y+gLOqNQFWS3NZI6bdaCNVLSV78WF//J17G1/sqzfZuKvx1mYRbaXkHusvFzoa8wEqXiFGNpnYUlZoFw+7xCIo4T05hftilbqx1tl9xW4IOVL33/qJ5od/nZN68hkKNfaQ5wAxa0m1ZTuVXZP8CmtUleRxAoGAQcz+GcrzLybY8EMOhYRbb79H8tQ+SoFkTOmJV4ZQDxzg18dPd8+U3YaMp3QngxncOSpjSwsuqpw/SqxHBQE/v91uEzLfPPS2QJ5COBvXM2Y7PsSmMnukIOM0NrtU8MIonv+l7UsHDeCllqe5+uRPpBUUk2mljPVprXo0SDjQr1U=';
    var aesSharedKey = '7l00PvmXMD9i1z0Q72O7RNQc6D9/9k9FrqfvCZcEBqs=';
    var encryptedSharedKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);
    var publicKeyCheckSum =
        EncryptionUtil.md5CheckSum(aliceEncryptionPublicKey);
    var location = 'California';
    var encryptedLocation = EncryptionUtil.encryptValue(location, aesSharedKey);
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
    sharedKey.metadata = (Metadata()..pubKeyCS = publicKeyCheckSum);
    var decryptedLocation =
        await sharedKeyDecryption.decrypt(sharedKey, encryptedLocation);
    expect(decryptedLocation, location);
  });

  test('test to check shared key decryption - with IV', () async {
    var sharedKeyDecryption = SharedKeyDecryption(mockAtClient);
    var aliceEncryptionPublicKey =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0sYjWt6TTikajY3HjvdN3sn2Ve3O+i84/gBrWPqhGNSdImz3W2l9dMSHm4wyixsxMSQaL+rECjwnvp3sRdW3M51sDCvWa06MLptvdrtnMjzDrvP45hUJY/i6WeDW8qeEOf9zuo+BLcQ3pkV1KZyhBj80OndLS/y00T8fYB9KnS5Z/iN7KW7Hxuv0isMPXxL1i8AZos7m5GuWq7CfRFKJIZ6vqYBUJCVSQCUVo1llyjElodSywcf1KjCvBOKuMPnUQCs+pKJt3QMFI0U7D+yinnlEdr6TBfOzMMPS3Du1LHpTGt7rqyxZrX8p4kpVb/CyL6wkelMuahHDOeNFBNyF0wIDAQAB';
    var aliceEncryptionPrivateKey =
        'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDSxiNa3pNOKRqNjceO903eyfZV7c76Lzj+AGtY+qEY1J0ibPdbaX10xIebjDKLGzExJBov6sQKPCe+nexF1bcznWwMK9ZrTowum292u2cyPMOu8/jmFQlj+LpZ4Nbyp4Q5/3O6j4EtxDemRXUpnKEGPzQ6d0tL/LTRPx9gH0qdLln+I3spbsfG6/SKww9fEvWLwBmizubka5arsJ9EUokhnq+pgFQkJVJAJRWjWWXKMSWh1LLBx/UqMK8E4q4w+dRAKz6kom3dAwUjRTsP7KKeeUR2vpMF87Mww9LcO7UselMa3uurLFmtfyniSlVv8LIvrCR6Uy5qEcM540UE3IXTAgMBAAECggEAfImMLE3k1cLdqJQEPIoNHb1RatZXfGXYk+QliW6VLzm5GrUttnpvIUZaJeNBngXUHAgL3RInATEn/q4LA/xSAhJa3Bou2DqSA5vd0VbLk9hpev82qqP1Z3d4jFCYUMoAC9DPTYUrO6J7iyfxIUQltK41qvH/sIdBQ327iS0UBihhiKg16BOKG4SoFJHZfhhL6m86+jnsaBTaAWb8hpa/Mwqs5eDHF78DHK8o+4Q6DufDi34nCwdxEexL3MFa9L0qGbQAqJshgDcJ6yxUzb5+tw3XXpiE0yG9aZ5gPaS2UgOYY1m2mmF4RjFSiLmKyN99H99ycA59enVFyfYh4SnuMQKBgQDq9IwkVyDkNxkaW6hyYMzBwNqId74JUNjXCWyzDJ58JWaNvFYYY4ujSCLTdfdugmVTIUjqXMVsxzq/e9jNaOj7u27/3inqn1VC88GFJJiUiLQcTP1T5ySP4jy5GVrhQ1zP8PtiRqE34emYfVY8OLa7bwf5CufgbL5RzKPrfIafKQKBgQDlpx8DoETRPE7FyZJg9xiUTyZmI/P6RmhCO86knbQa4hEWiCuEIiOheJQxdcW6yCNImbJNSEFUnpweiHEw4xdMmlpR4JDkvsGOyjLI6Y36Yxbi+AipvTuYZ/La7fuOeEjwD7OlgJmva2jEQL6GlhmTibgt5dfwzOiAP0gC4tXomwKBgQDAnZDSLfeSADV9LU0vz3mtEYxWOkw52OSbjWdmdd7ricHESnUOc3VDe9zJHLmnCBFHEE91im5zWfUoi8BVzT7LOIKsEpaseMjuJWUt4K2Rf2ygkuFPSnvn1SHQ4R9m8tGAy19a1upOJM9bKs1qe1ga2tBfc3havOtdpfVwFVtL2QKBgDFsPehx3V2KNQmrz6y+gLOqNQFWS3NZI6bdaCNVLSV78WF//J17G1/sqzfZuKvx1mYRbaXkHusvFzoa8wEqXiFGNpnYUlZoFw+7xCIo4T05hftilbqx1tl9xW4IOVL33/qJ5od/nZN68hkKNfaQ5wAxa0m1ZTuVXZP8CmtUleRxAoGAQcz+GcrzLybY8EMOhYRbb79H8tQ+SoFkTOmJV4ZQDxzg18dPd8+U3YaMp3QngxncOSpjSwsuqpw/SqxHBQE/v91uEzLfPPS2QJ5COBvXM2Y7PsSmMnukIOM0NrtU8MIonv+l7UsHDeCllqe5+uRPpBUUk2mljPVprXo0SDjQr1U=';
    var aesSharedKey = '7l00PvmXMD9i1z0Q72O7RNQc6D9/9k9FrqfvCZcEBqs=';
    var encryptedSharedKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);
    var publicKeyCheckSum =
        EncryptionUtil.md5CheckSum(aliceEncryptionPublicKey);
    var location = 'California';
    var ivBase64String = 'YmFzZTY0IGVuY29kaW5n';
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

  test('test to check shared key decryption with IV', () async {
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
