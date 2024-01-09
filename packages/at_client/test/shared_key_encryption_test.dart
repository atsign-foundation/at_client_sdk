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

  test('test to check shared key encryption - without IV', () async {
    var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
    var bobMockAtClient = MockAtClientImpl();
    var bobMockLocalSecondary = MockLocalSecondary();
    var bobEncryptionPublicKey =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAne3nQ++AIaeL/JWNDmZhJFY/iV7ZMAunsHcfTOH7G6cVnl6tssqKuune5jHcPdoq1JdzNj0O/tP00+CFeiKROEPwXLeVbyNdZ+AWjO7dUCHf9q9TX6rE/6WVzcVptyD7q4RIBSijOjJiduE32QD1iqckQ8lKa4HmNJoe4a1IaiyqEFyD8sZyiqTHI2GK7qHiHoIH32YkP/c60xvE7rZ8uS0fqr7yoq7fcLCiPZk44OCLBjSx+wPwlqfDaq4ogyeamte1mIePPPLjQCDPyLvktAotXNtOkZ2KzYBr7A/GFbYT39OFM2QmE22mVfmEniBhrDRhhFTvsIXuxSRE9UAVFwIDAQAB';
    var bobEncryptionPrivateKey =
        'MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCd7edD74Ahp4v8lY0OZmEkVj+JXtkwC6ewdx9M4fsbpxWeXq2yyoq66d7mMdw92irUl3M2PQ7+0/TT4IV6IpE4Q/Bct5VvI11n4BaM7t1QId/2r1NfqsT/pZXNxWm3IPurhEgFKKM6MmJ24TfZAPWKpyRDyUprgeY0mh7hrUhqLKoQXIPyxnKKpMcjYYruoeIeggffZiQ/9zrTG8Tutny5LR+qvvKirt9wsKI9mTjg4IsGNLH7A/CWp8NqriiDJ5qa17WYh4888uNAIM/Iu+S0Ci1c206RnYrNgGvsD8YVthPf04UzZCYTbaZV+YSeIGGsNGGEVO+whe7FJET1QBUXAgMBAAECggEAWtxJxqsfM72aa1p7SgKa9vXsHhOErwC1nHAcgPYuq00owfHEy219/WWaSSP8i1VeeOsdbOIaI4A8hj3RbWA/3ngv7JfukH9vONkTAEhY6cZjfSCHvi2Yo2BX3IgsdyCxyo8ThGxJ5KyiO7T9lYrYucnJsno3p7yXfkIBbGNumy5lzmxnB9tUpteu/742/kebuyKO9zX/ssjjn1Fg4WrxMRtBGt8sRe6m1Gv1NOS0DxhII52ElFSCX66fQeA5JR3bwNpqAhBpUZbbbigqk5VARpGObWZCUh8dJjpsF5BUl1NOrOVYgQ/7uxukDmZ6O/iTN/7u1WvdiB13JbSNNuMqeQKBgQDyTQeADnCBkY8KwV3hZeQo9gXrdTbv5IOmvxjpoT8+bSgTYMq6U8VCdV8PDEhH8m3UF8SA7a7B97IxQRTHLvYhxK3Kn8zKiFyNnPqwQYpmkciUA2KqSqIT4cW1VaYK4o1K8shcqDCDxBa4oI9jz7lx5hr7SvgmKrDkcAevINJ5XQKBgQCm27ZCRAnsCue7H7g9Katz2GnmlrsalCraUI23FqloPhIp+o4aqFaWTOBM9mkgNxnMCnKNlMNn2wUH+mpQnFbIDxtH0MGyqmNdf9+G9/ZPJQHU4ypcLukOZLOhKqc3Y8zjZ2CoDjdiHTW0xyplqa99DAKbopNLRW7uNz1b5fu9AwKBgCHflu7WFfBnMwIj6kX6gp0fV9CFAHslDSqgiJEQ09CcXf/nhi/qSidyVSm7Y9d7EtOVxwjnMYk4YZb1LDx0WkB6SHmNQYoG6jl5+qntX7XbJ5lZp896w5HX/FXPdXkMFwilTFF3yeCB51NETwd7IMfFjXwYDPz49uXYq5pWElaZAoGAeLeAVtTOsNz65iB+tJFPH5K0m0T1vLbxgdzBinJ0wZwWnBRPdu3PJxIbPNMRH2N94Ga2lcPI03xbWXhMLmHNTxPO0tgvKsmm9eAroYQHyR6nApQO835k0ir84l7vd11WwDbscOlIHE2xq0ZkYASxl7B2uo6WLeDf7qw8Uh5DUG0CgYAnSWae63GKBQxUQ5M9ILL9XPzfsOweZ+EaWjz/CgibdGf1EmUXErcKJaRUvGzsIkJlL907tr2FDhNB4eB+5uORrZtTNxP1Gz4EH0ORYNDa2sAlQ+ma8ruMXuOuEgL8W2/k8Buf/tG9TL6FACDuN1Rj1aLFkjk0bGM5oztwOtxzyg==';
    var bobEncryptionKeyPair = AtEncryptionKeyPair.create(
        bobEncryptionPublicKey, bobEncryptionPrivateKey);

    AtChopsKeys bobAtChopsKeys = AtChopsKeys.create(bobEncryptionKeyPair, null);
    var bobAtChopsImpl = AtChopsImpl(bobAtChopsKeys);
    when(() => bobMockAtClient.atChops).thenAnswer((_) => bobAtChopsImpl);
    when(() => bobMockAtClient.getLocalSecondary())
        .thenAnswer((_) => bobMockLocalSecondary);
    when(() => bobMockAtClient.getCurrentAtSign()).thenReturn('@bob');
    when(() => bobMockLocalSecondary.getEncryptionPublicKey('@bob'))
        .thenAnswer((_) => Future.value(bobEncryptionPublicKey));
    var sharedKeyDecryption = SharedKeyDecryption(bobMockAtClient);
    var aliceEncryptionPublicKey =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0sYjWt6TTikajY3HjvdN3sn2Ve3O+i84/gBrWPqhGNSdImz3W2l9dMSHm4wyixsxMSQaL+rECjwnvp3sRdW3M51sDCvWa06MLptvdrtnMjzDrvP45hUJY/i6WeDW8qeEOf9zuo+BLcQ3pkV1KZyhBj80OndLS/y00T8fYB9KnS5Z/iN7KW7Hxuv0isMPXxL1i8AZos7m5GuWq7CfRFKJIZ6vqYBUJCVSQCUVo1llyjElodSywcf1KjCvBOKuMPnUQCs+pKJt3QMFI0U7D+yinnlEdr6TBfOzMMPS3Du1LHpTGt7rqyxZrX8p4kpVb/CyL6wkelMuahHDOeNFBNyF0wIDAQAB';

    var aliceEncryptionPrivateKey =
        'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDSxiNa3pNOKRqNjceO903eyfZV7c76Lzj+AGtY+qEY1J0ibPdbaX10xIebjDKLGzExJBov6sQKPCe+nexF1bcznWwMK9ZrTowum292u2cyPMOu8/jmFQlj+LpZ4Nbyp4Q5/3O6j4EtxDemRXUpnKEGPzQ6d0tL/LTRPx9gH0qdLln+I3spbsfG6/SKww9fEvWLwBmizubka5arsJ9EUokhnq+pgFQkJVJAJRWjWWXKMSWh1LLBx/UqMK8E4q4w+dRAKz6kom3dAwUjRTsP7KKeeUR2vpMF87Mww9LcO7UselMa3uurLFmtfyniSlVv8LIvrCR6Uy5qEcM540UE3IXTAgMBAAECggEAfImMLE3k1cLdqJQEPIoNHb1RatZXfGXYk+QliW6VLzm5GrUttnpvIUZaJeNBngXUHAgL3RInATEn/q4LA/xSAhJa3Bou2DqSA5vd0VbLk9hpev82qqP1Z3d4jFCYUMoAC9DPTYUrO6J7iyfxIUQltK41qvH/sIdBQ327iS0UBihhiKg16BOKG4SoFJHZfhhL6m86+jnsaBTaAWb8hpa/Mwqs5eDHF78DHK8o+4Q6DufDi34nCwdxEexL3MFa9L0qGbQAqJshgDcJ6yxUzb5+tw3XXpiE0yG9aZ5gPaS2UgOYY1m2mmF4RjFSiLmKyN99H99ycA59enVFyfYh4SnuMQKBgQDq9IwkVyDkNxkaW6hyYMzBwNqId74JUNjXCWyzDJ58JWaNvFYYY4ujSCLTdfdugmVTIUjqXMVsxzq/e9jNaOj7u27/3inqn1VC88GFJJiUiLQcTP1T5ySP4jy5GVrhQ1zP8PtiRqE34emYfVY8OLa7bwf5CufgbL5RzKPrfIafKQKBgQDlpx8DoETRPE7FyZJg9xiUTyZmI/P6RmhCO86knbQa4hEWiCuEIiOheJQxdcW6yCNImbJNSEFUnpweiHEw4xdMmlpR4JDkvsGOyjLI6Y36Yxbi+AipvTuYZ/La7fuOeEjwD7OlgJmva2jEQL6GlhmTibgt5dfwzOiAP0gC4tXomwKBgQDAnZDSLfeSADV9LU0vz3mtEYxWOkw52OSbjWdmdd7ricHESnUOc3VDe9zJHLmnCBFHEE91im5zWfUoi8BVzT7LOIKsEpaseMjuJWUt4K2Rf2ygkuFPSnvn1SHQ4R9m8tGAy19a1upOJM9bKs1qe1ga2tBfc3havOtdpfVwFVtL2QKBgDFsPehx3V2KNQmrz6y+gLOqNQFWS3NZI6bdaCNVLSV78WF//J17G1/sqzfZuKvx1mYRbaXkHusvFzoa8wEqXiFGNpnYUlZoFw+7xCIo4T05hftilbqx1tl9xW4IOVL33/qJ5od/nZN68hkKNfaQ5wAxa0m1ZTuVXZP8CmtUleRxAoGAQcz+GcrzLybY8EMOhYRbb79H8tQ+SoFkTOmJV4ZQDxzg18dPd8+U3YaMp3QngxncOSpjSwsuqpw/SqxHBQE/v91uEzLfPPS2QJ5COBvXM2Y7PsSmMnukIOM0NrtU8MIonv+l7UsHDeCllqe5+uRPpBUUk2mljPVprXo0SDjQr1U=';
    var aesSharedKey = '7l00PvmXMD9i1z0Q72O7RNQc6D9/9k9FrqfvCZcEBqs=';
    var sharedKeyEncryptedWithAlicePublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);
    var sharedKeyEncryptedWithBobPublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, bobEncryptionPublicKey);
    var bobPublicKeyCheckSum =
        EncryptionUtil.md5CheckSum(bobEncryptionPublicKey);
    var location = 'California';
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        aliceEncryptionPublicKey, aliceEncryptionPrivateKey);

    AtChopsKeys atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
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

  test('test to check shared key encryption - with IV', () async {
    var sharedKeyEncryption = SharedKeyEncryption(mockAtClient);
    var bobMockAtClient = MockAtClientImpl();
    var bobMockLocalSecondary = MockLocalSecondary();
    var bobEncryptionPublicKey =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAne3nQ++AIaeL/JWNDmZhJFY/iV7ZMAunsHcfTOH7G6cVnl6tssqKuune5jHcPdoq1JdzNj0O/tP00+CFeiKROEPwXLeVbyNdZ+AWjO7dUCHf9q9TX6rE/6WVzcVptyD7q4RIBSijOjJiduE32QD1iqckQ8lKa4HmNJoe4a1IaiyqEFyD8sZyiqTHI2GK7qHiHoIH32YkP/c60xvE7rZ8uS0fqr7yoq7fcLCiPZk44OCLBjSx+wPwlqfDaq4ogyeamte1mIePPPLjQCDPyLvktAotXNtOkZ2KzYBr7A/GFbYT39OFM2QmE22mVfmEniBhrDRhhFTvsIXuxSRE9UAVFwIDAQAB';
    var bobEncryptionPrivateKey =
        'MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCd7edD74Ahp4v8lY0OZmEkVj+JXtkwC6ewdx9M4fsbpxWeXq2yyoq66d7mMdw92irUl3M2PQ7+0/TT4IV6IpE4Q/Bct5VvI11n4BaM7t1QId/2r1NfqsT/pZXNxWm3IPurhEgFKKM6MmJ24TfZAPWKpyRDyUprgeY0mh7hrUhqLKoQXIPyxnKKpMcjYYruoeIeggffZiQ/9zrTG8Tutny5LR+qvvKirt9wsKI9mTjg4IsGNLH7A/CWp8NqriiDJ5qa17WYh4888uNAIM/Iu+S0Ci1c206RnYrNgGvsD8YVthPf04UzZCYTbaZV+YSeIGGsNGGEVO+whe7FJET1QBUXAgMBAAECggEAWtxJxqsfM72aa1p7SgKa9vXsHhOErwC1nHAcgPYuq00owfHEy219/WWaSSP8i1VeeOsdbOIaI4A8hj3RbWA/3ngv7JfukH9vONkTAEhY6cZjfSCHvi2Yo2BX3IgsdyCxyo8ThGxJ5KyiO7T9lYrYucnJsno3p7yXfkIBbGNumy5lzmxnB9tUpteu/742/kebuyKO9zX/ssjjn1Fg4WrxMRtBGt8sRe6m1Gv1NOS0DxhII52ElFSCX66fQeA5JR3bwNpqAhBpUZbbbigqk5VARpGObWZCUh8dJjpsF5BUl1NOrOVYgQ/7uxukDmZ6O/iTN/7u1WvdiB13JbSNNuMqeQKBgQDyTQeADnCBkY8KwV3hZeQo9gXrdTbv5IOmvxjpoT8+bSgTYMq6U8VCdV8PDEhH8m3UF8SA7a7B97IxQRTHLvYhxK3Kn8zKiFyNnPqwQYpmkciUA2KqSqIT4cW1VaYK4o1K8shcqDCDxBa4oI9jz7lx5hr7SvgmKrDkcAevINJ5XQKBgQCm27ZCRAnsCue7H7g9Katz2GnmlrsalCraUI23FqloPhIp+o4aqFaWTOBM9mkgNxnMCnKNlMNn2wUH+mpQnFbIDxtH0MGyqmNdf9+G9/ZPJQHU4ypcLukOZLOhKqc3Y8zjZ2CoDjdiHTW0xyplqa99DAKbopNLRW7uNz1b5fu9AwKBgCHflu7WFfBnMwIj6kX6gp0fV9CFAHslDSqgiJEQ09CcXf/nhi/qSidyVSm7Y9d7EtOVxwjnMYk4YZb1LDx0WkB6SHmNQYoG6jl5+qntX7XbJ5lZp896w5HX/FXPdXkMFwilTFF3yeCB51NETwd7IMfFjXwYDPz49uXYq5pWElaZAoGAeLeAVtTOsNz65iB+tJFPH5K0m0T1vLbxgdzBinJ0wZwWnBRPdu3PJxIbPNMRH2N94Ga2lcPI03xbWXhMLmHNTxPO0tgvKsmm9eAroYQHyR6nApQO835k0ir84l7vd11WwDbscOlIHE2xq0ZkYASxl7B2uo6WLeDf7qw8Uh5DUG0CgYAnSWae63GKBQxUQ5M9ILL9XPzfsOweZ+EaWjz/CgibdGf1EmUXErcKJaRUvGzsIkJlL907tr2FDhNB4eB+5uORrZtTNxP1Gz4EH0ORYNDa2sAlQ+ma8ruMXuOuEgL8W2/k8Buf/tG9TL6FACDuN1Rj1aLFkjk0bGM5oztwOtxzyg==';
    var bobEncryptionKeyPair = AtEncryptionKeyPair.create(
        bobEncryptionPublicKey, bobEncryptionPrivateKey);

    AtChopsKeys bobAtChopsKeys = AtChopsKeys.create(bobEncryptionKeyPair, null);
    var bobAtChopsImpl = AtChopsImpl(bobAtChopsKeys);
    when(() => bobMockAtClient.atChops).thenAnswer((_) => bobAtChopsImpl);
    when(() => bobMockAtClient.getLocalSecondary())
        .thenAnswer((_) => bobMockLocalSecondary);
    when(() => bobMockAtClient.getCurrentAtSign()).thenReturn('@bob');
    when(() => bobMockLocalSecondary.getEncryptionPublicKey('@bob'))
        .thenAnswer((_) => Future.value(bobEncryptionPublicKey));
    var sharedKeyDecryption = SharedKeyDecryption(bobMockAtClient);
    var aliceEncryptionPublicKey =
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0sYjWt6TTikajY3HjvdN3sn2Ve3O+i84/gBrWPqhGNSdImz3W2l9dMSHm4wyixsxMSQaL+rECjwnvp3sRdW3M51sDCvWa06MLptvdrtnMjzDrvP45hUJY/i6WeDW8qeEOf9zuo+BLcQ3pkV1KZyhBj80OndLS/y00T8fYB9KnS5Z/iN7KW7Hxuv0isMPXxL1i8AZos7m5GuWq7CfRFKJIZ6vqYBUJCVSQCUVo1llyjElodSywcf1KjCvBOKuMPnUQCs+pKJt3QMFI0U7D+yinnlEdr6TBfOzMMPS3Du1LHpTGt7rqyxZrX8p4kpVb/CyL6wkelMuahHDOeNFBNyF0wIDAQAB';

    var aliceEncryptionPrivateKey =
        'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDSxiNa3pNOKRqNjceO903eyfZV7c76Lzj+AGtY+qEY1J0ibPdbaX10xIebjDKLGzExJBov6sQKPCe+nexF1bcznWwMK9ZrTowum292u2cyPMOu8/jmFQlj+LpZ4Nbyp4Q5/3O6j4EtxDemRXUpnKEGPzQ6d0tL/LTRPx9gH0qdLln+I3spbsfG6/SKww9fEvWLwBmizubka5arsJ9EUokhnq+pgFQkJVJAJRWjWWXKMSWh1LLBx/UqMK8E4q4w+dRAKz6kom3dAwUjRTsP7KKeeUR2vpMF87Mww9LcO7UselMa3uurLFmtfyniSlVv8LIvrCR6Uy5qEcM540UE3IXTAgMBAAECggEAfImMLE3k1cLdqJQEPIoNHb1RatZXfGXYk+QliW6VLzm5GrUttnpvIUZaJeNBngXUHAgL3RInATEn/q4LA/xSAhJa3Bou2DqSA5vd0VbLk9hpev82qqP1Z3d4jFCYUMoAC9DPTYUrO6J7iyfxIUQltK41qvH/sIdBQ327iS0UBihhiKg16BOKG4SoFJHZfhhL6m86+jnsaBTaAWb8hpa/Mwqs5eDHF78DHK8o+4Q6DufDi34nCwdxEexL3MFa9L0qGbQAqJshgDcJ6yxUzb5+tw3XXpiE0yG9aZ5gPaS2UgOYY1m2mmF4RjFSiLmKyN99H99ycA59enVFyfYh4SnuMQKBgQDq9IwkVyDkNxkaW6hyYMzBwNqId74JUNjXCWyzDJ58JWaNvFYYY4ujSCLTdfdugmVTIUjqXMVsxzq/e9jNaOj7u27/3inqn1VC88GFJJiUiLQcTP1T5ySP4jy5GVrhQ1zP8PtiRqE34emYfVY8OLa7bwf5CufgbL5RzKPrfIafKQKBgQDlpx8DoETRPE7FyZJg9xiUTyZmI/P6RmhCO86knbQa4hEWiCuEIiOheJQxdcW6yCNImbJNSEFUnpweiHEw4xdMmlpR4JDkvsGOyjLI6Y36Yxbi+AipvTuYZ/La7fuOeEjwD7OlgJmva2jEQL6GlhmTibgt5dfwzOiAP0gC4tXomwKBgQDAnZDSLfeSADV9LU0vz3mtEYxWOkw52OSbjWdmdd7ricHESnUOc3VDe9zJHLmnCBFHEE91im5zWfUoi8BVzT7LOIKsEpaseMjuJWUt4K2Rf2ygkuFPSnvn1SHQ4R9m8tGAy19a1upOJM9bKs1qe1ga2tBfc3havOtdpfVwFVtL2QKBgDFsPehx3V2KNQmrz6y+gLOqNQFWS3NZI6bdaCNVLSV78WF//J17G1/sqzfZuKvx1mYRbaXkHusvFzoa8wEqXiFGNpnYUlZoFw+7xCIo4T05hftilbqx1tl9xW4IOVL33/qJ5od/nZN68hkKNfaQ5wAxa0m1ZTuVXZP8CmtUleRxAoGAQcz+GcrzLybY8EMOhYRbb79H8tQ+SoFkTOmJV4ZQDxzg18dPd8+U3YaMp3QngxncOSpjSwsuqpw/SqxHBQE/v91uEzLfPPS2QJ5COBvXM2Y7PsSmMnukIOM0NrtU8MIonv+l7UsHDeCllqe5+uRPpBUUk2mljPVprXo0SDjQr1U=';
    var aesSharedKey = '7l00PvmXMD9i1z0Q72O7RNQc6D9/9k9FrqfvCZcEBqs=';
    var sharedKeyEncryptedWithAlicePublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, aliceEncryptionPublicKey);
    var sharedKeyEncryptedWithBobPublicKey =
        EncryptionUtil.encryptKey(aesSharedKey, bobEncryptionPublicKey);
    var bobPublicKeyCheckSum =
        EncryptionUtil.md5CheckSum(bobEncryptionPublicKey);
    var location = 'California';
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        aliceEncryptionPublicKey, aliceEncryptionPrivateKey);

    AtChopsKeys atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, null);
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
    var ivBase64String = 'YmFzZTY0IGVuY29kaW5n';
    sharedKey.metadata = (Metadata()
      ..pubKeyCS = bobPublicKeyCheckSum
      ..ivNonce = ivBase64String);
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
