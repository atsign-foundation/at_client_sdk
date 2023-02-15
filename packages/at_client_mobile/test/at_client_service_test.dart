import 'dart:convert';

import 'package:at_chops/at_chops.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/atsign_key.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:at_client/src/service/sync_service.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

class MockKeyChainManager extends Mock implements KeyChainManager {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtClientAuthenticator extends Mock implements AtClientAuthenticator {}

class MockSyncService extends Mock implements SyncService {}

class FakeAtSignKey extends Fake implements AtsignKey {}

class FakeUpdateVerbBuilder extends Fake implements UpdateVerbBuilder {}

class FakeAtClientPreferences extends Fake implements AtClientPreference {}

void main() {
  String atSign = '@bob';

  late AtClientPreference atClientPreference;
  late AtLookupImpl mockAtLookupImpl;
  late KeyChainManager mockKeyChainManager;
  late AtClientManager mockAtClientManager;
  late AtClient mockAtClient;
  late LocalSecondary mockLocalSecondary;
  late RemoteSecondary mockRemoteSecondary;
  late AtClientAuthenticator mockAtClientAuthenticator;
  late SyncService mockSyncService;
  AtChopsImpl? atChopsImpl;

  void setUpMethod() {
    registerFallbackValue(FakeAtSignKey());
    registerFallbackValue(FakeUpdateVerbBuilder());
    registerFallbackValue(FakeAtClientPreferences());

    atClientPreference = AtClientPreference();
    mockAtLookupImpl = MockAtLookupImpl();
    mockKeyChainManager = MockKeyChainManager();
    mockAtClientManager = MockAtClientManager();
    mockAtClient = MockAtClient();
    mockLocalSecondary = MockLocalSecondary();
    mockRemoteSecondary = MockRemoteSecondary();
    mockAtClientAuthenticator = MockAtClientAuthenticator();
    mockSyncService = MockSyncService();

    when(() => mockAtLookupImpl.authenticate(any()))
        .thenAnswer((_) => Future.value(true));
    when(() => mockAtLookupImpl.pkamAuthenticate())
        .thenAnswer((_) => Future.value(true));
    when(() => mockAtLookupImpl.close()).thenAnswer((_) async => {});

    when(() => mockAtClientManager.setCurrentAtSign(
        any(), any(), any(that: CustomAtClientPref()),
        atChops: any(named: 'atChops'))).thenAnswer((Invocation invocation) {
      var list = invocation.namedArguments.values.toList();
      list.retainWhere((element) => element is AtChopsImpl);
      atChopsImpl = list[0];
      return Future.value(mockAtClientManager);
    });
    when(() => mockAtClientManager.atClient).thenAnswer((_) => mockAtClient);

    when(() => mockAtClient.getLocalSecondary())
        .thenAnswer((_) => mockLocalSecondary);
    when(() => mockAtClient.atChops).thenAnswer((_) => atChopsImpl);
    when(() => mockAtClient.getRemoteSecondary())
        .thenAnswer((_) => mockRemoteSecondary);
    when(() => mockAtClient.syncService).thenAnswer((_) => mockSyncService);

    when(() => mockRemoteSecondary.atLookUp)
        .thenAnswer((_) => mockAtLookupImpl);

    when(() => mockSyncService.sync()).thenAnswer((_) => {});

    when(() => mockLocalSecondary.putValue(any(), any()))
        .thenAnswer((_) => Future.value(true));
    when(() => mockLocalSecondary.executeVerb(any(that: CustomVerbBuilder()),
        sync: true)).thenAnswer((_) => Future.value('data:1'));
    when(() => mockLocalSecondary.getPrivateKey())
        .thenAnswer((_) => Future.value('dummy_private_key'));
    when(() => mockLocalSecondary.getPublicKey())
        .thenAnswer((_) => Future.value('dummy_public_key'));
    when(() => mockLocalSecondary.getEncryptionPrivateKey())
        .thenAnswer((_) => Future.value('dummy_encryption_private_key'));
    when(() => mockLocalSecondary.getEncryptionPublicKey(any()))
        .thenAnswer((_) => Future.value('dummy_encryption_public_key'));
    when(() => mockLocalSecondary.getEncryptionSelfKey())
        .thenAnswer((_) => Future.value('dummy_self_encryption_key'));

    when(() => mockKeyChainManager.storePkamKeysToKeychain(any(),
            privateKey: any(named: 'privateKey'),
            publicKey: any(named: 'publicKey')))
        .thenAnswer((_) => Future.value(true));
    when(() => mockKeyChainManager.readAtsign(name: any(named: 'name')))
        .thenAnswer((_) => Future.value(AtsignKey(atSign: '@bob')));
    when(() => mockKeyChainManager.storeAtSign(
            atSign: any(named: 'atSign', that: CustomAtSignMatcher())))
        .thenAnswer((_) => Future.value(true));
    when(() => mockKeyChainManager.storeCredentialToKeychain(any(),
            privateKey: any(named: 'privateKey'),
            publicKey: any(named: 'publicKey')))
        .thenAnswer((invocation) => Future.value(true));
    when(() => mockKeyChainManager.getPkamPublicKey(any()))
        .thenAnswer((_) => Future.value('dummy_public_key'));
    when(() => mockKeyChainManager.getEncryptionPrivateKey(any()))
        .thenAnswer((_) => Future.value('dummy_encryption_private_key'));
    when(() => mockKeyChainManager.getEncryptionPublicKey(any()))
        .thenAnswer((_) => Future.value('dummy_encryption_public_key'));
    when(() => mockKeyChainManager.getSelfEncryptionAESKey(any()))
        .thenAnswer((_) => Future.value('dummy_self_encryption_key'));
  }

  group('A group of tests to validate authenticate method', () {
    setUp(() => setUpMethod());
    test(
        'A test to verify authenticate function returns true when atKeys is uploaded',
        () async {
      // jsonData represents the atKeys file data
      String encryptedPkamPrivateKey =
          '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';
      String encryptedPkamPublicKey =
          'x/HnmsEMLlG1t1NhlbnB2Yo06lSRuHlrdxDkfPvZHqEI0UE09apcZEKqq/mUlW0pB0X1aFUOPsSlTcjvOvptiRPgo6oD48xANY8TSduQgn94wxsvZlP6xL0Fht8sIz+f1Mkok5SUIbDuVANObFLm2zf9Ipgn2eQ+y2PjjKaI6Dhe3yUr5SFxuv6dp2UeuN5+PGYo2ZCOgeo8WWxThh7PBpgac0/AXCjcQiiNvY59eNQxn/DXEJeXmhBSViI7pCmvW4O7Yo34uTX/TYPvaaBoJlDwwI9q0oR2zDKpi4pObvSdIZhaJ+WEbKy7RACQiN/GfkOLSegWpLXKYYkVps2dRNO251R3uTitfu9m8BO1Gi01H3s2CMKmqi857MkcNcPGU7D1XXW6r8YddfraAPwvUoYGUIcl7dWudwXDJKfjDpXDaklUjZJSGfoSbDvQ6x6a5sV1XZ9WtZJokAIjz4aPd+GCCC+ukSLrTFgGH2TJyFgTAg18Gwdh7SegISwvSCdg6FpiqijMdEPUP6jCRGfT9g==';
      String encryptedEncryptionPrivateKey =
          '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';
      String encryptedEncryptionPublicKey =
          'x/HnmsEMLlG1t1NhlbnB2Yo06lSRuHlrdxDkfPvZHqEI0UE09apcZEKqq/mRg38WMlnINGNbBbD/T7jCMrAK8DDiwrcB5oAYKbsNCq66+3p62mgAblProe1zm8gGSwqD9PgXvqX4Oorna152XEnI0ib8FK8k2NBIyDTxucKq1AA8yH5dii5oscCTk1sP38hgGDgsyJKSw9p6eHZM9GCJAvMiRAv4ZheHUiiLhdxxfNASsraycOqZ0zExcRMHlAbsC4z5TJDyvQu4ctihfMAILmms3rhD9Ml5+Cb4kY9IfM2hAaIGW7vDT5bJXQnriryfTHKfXKIVzq7iMPhHo5GSetCQ7Ahb70SmHO5zhlyxQSsCWVkXIbq0sQgS8ukrMsiYJbmyVmXXofhne8rYJqIrTbJEQqgn0bezOST3O4OeVJbYdWRw57hiBeNoJ0LI+kmG6e9sQIllp4927h4k45iLdpumORWckn/JQQJkAVicg0QMVgwvCilEwguzOCggTiAGmVpiqijMdEPUP6jCRGfT9g==';

      // Decrypted keys for asserting.
      String decryptedPKAMPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlpgqDIRoO0jD4wDZg/W/HjNIHPx0hNduGb+GjnEjbYs1cCHxCCREActLy8Oy9R0sfieOwVXSq1m058VQ/HrAUyhC5FXBQEexA+fSS2BcRiurvfKKAJ5+Xrc0jHR4he2T6MinMXq612vqP+AdNal4dyiKmGMl6Vo8Z+TxPotdZDf9Sz+sdKZSEqKk381JVBRDKDR4yyzr+7SIP978D18ODUEhC4DH6vt9dl+CRqjLa3dJmJfyE426EE09zUjvJdv1In4jc++lsu/6zpUep/5wMlBSANiKK615TX3HbglvoAEQWG+4FZpbIBiMeVrTn6Sdm8//Ye4apDMXdaOlK1NP5QIDAQAB';
      String decryptedPKAMPrivateKey =
          'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCWmCoMhGg7SMPjANmD9b8eM0gc/HSE124Zv4aOcSNtizVwIfEIJEQBy0vLw7L1HSx+J47BVdKrWbTnxVD8esBTKELkVcFAR7ED59JLYFxGK6u98ooAnn5etzSMdHiF7ZPoyKcxerrXa+o/4B01qXh3KIqYYyXpWjxn5PE+i11kN/1LP6x0plISoqTfzUlUFEMoNHjLLOv7tIg/3vwPXw4NQSELgMfq+312X4JGqMtrd0mYl/ITjboQTT3NSO8l2/UifiNz76Wy7/rOlR6n/nAyUFIA2IorrXlNfcduCW+gARBYb7gVmlsgGIx5WtOfpJ2bz/9h7hqkMxd1o6UrU0/lAgMBAAECggEAW/upg2fEuqFhdOBp+9441FuCaqIREar8hyGjMJIOj7R9+XXh4ZU1LNtd+qIYRvuA17WVzqV7PkpW41J0eyMHIkPvR8TRe0/O4ZHRs1SyR/IYvrbMcEBe8793i2sAyt0ogQE+jkxmn3o85LMhZEuVV0MeFKJK39PMHbGLYSaC7tkMC/O+LGbFNBCgOZ3h6yaLpz4nVkCeXxuKpiR/zKfN2qe2VETb3Py4CI6EqCKSNDnrO6dF7p4Tbfcp7WHnuKsyGYmQuZXMJaibP+7RPxx8A72fX5n4sofHUBbugf3ryRz8vZKZeapRM3lKV2j3hwFwR1IMG6Ybu6ph9tRvP76eQQKBgQDLgckgsfnPMKKyrVcjeK0cIX6qGu88B9Gq4rxFzYtw4kKJVDrRyC1HAE3g8u8jiYISrqpod72zttmeJc2pwu0jfAPfAiqW6Fg/BR3OkoBgjVf9/qhJ/Nh1TIq+NQPACoeHlKIsBdwphNvhnXwJ0KILJSODTpksprkdtVtborknyQKBgQC9cGRbb/cOaHQh3YuZsXKLJp+cwIlGTkA/v+iXu1nOwOARhOJf4A+7QX8sGUpw54VaYmJ7ndvoI2H/yI7/5Hsmf0bzWIsyGKxfF2kOiJhTTeHpiIsI/TcOG+Wt1FISVP5MspDPwmnZKX0elP2BP7M84Msvb/VgYE6k4QX0p8KtPQKBgCjpS3y2Ksk7NsoCzOzFms938FXUGloQHFdlQ4Io4yprYgLnmveHbYrDheR+EhMr1qlY0cs0nz9ct/zyDpldJX0ntkOD1PoHdY4dwjNAAmzmnVTjeAN/wCg8nfvE/p8BvuNDvyJofy0dl3KQzVnPxnPFIJGKIIL4dWiCh/4xBVX5AoGAQ8li7+E5u3sfCzs2h/GaNjbE6Jdwx6qajPVD6n+M3FHiHAK76mjH2E7Qjdwi6hG+gyAvc2KCXSfEGn4OxXxhoN3saolljbCMhZ5f5mZ0c2KsEx/b+IR7Xd4XqsMN9ydYs+M1tFIyBBY3gmj36Xb80SzzJ+9dE3aCzbcDpY8eN1UCgYEApjHzXm+ncqHEJUWMuBUnZui92GzqFLwnYmDva11KcsYuH9JElfV3k1ic6XYlyZ239kjq25vhEvxEbHoYujw3pxbS5Lum8hnuW1BWybLddXNwLlSw6VqlilOErBE4Da6EO5xqQp1mUv+BhSWH8Kc3zxDMjDm/9c8UrC52xym/3yA=';
      String decryptedEncryptionPrivateKey =
          'MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCJ+42pSjfJ5DSe7jCh7RWSH9MlTiG3PPrYdEGHDoSNhtPflSiL6BhpEpodNMLSaYpWsoV9ad2vRgXqgN0qM3LufflkgAigpAU8ukzCUWs+7sHQZBPfiz/clO1GuajF7iV0CaOe7tJA7Hyod9StALDi/56kwhGqLi84rimLeNKxv7qCfOJowePJCrs5++KXQozQXWYoeeBrj1HGEWMCbuoaw3ihvwJPBo76GkR7seYcq9AlrFivf2HcvDaPx0fSMXejTS5aL0Kogz7hBrNNGi1WyjD51hZEvMssh1OYy6TKtYsj3veMO1zd9fBZT+9yXXNCZ3cXXnZqOHAetWEPsjoNAgMBAAECggEAQ7Bp4ECOebY/si+7H9SEnniKRmS72X5KuGDfvHd8w0j/K1Gq4Gdtgi4j+Gvnnv0zZjCRl+KVY+SABnhNBuTSXvjhnVHJ6bRM9WuXOERkziymW6qcrS9MltNgSy/NAbxAF1qbL96MuljJFoQiivQp0lH/62dg7xFVDQMzUj5lbdid0CIV9r9Jp6SxXCG8OTjhU8RupXyqWiIgg3xVr/Y2ayYnO2O8cnm9V8C0zTvX5290IijTfHXkbarGg0vY7sg2Krs1uk1sQ+70yHJSppTOfa+cfYLuoj4k+emqJWWn7TZKkTlfnc6ON566XN5eiH+t2AmKttW9MxWQhaWv50I7KQKBgQDH4yh3u8f+Pbj3L3SJMN0aQ/ZHMApJ96C+iAJRgYp0aYuVpHscQPRxS7p3JwT758cKdrUTHSji/t7PrtsLDlp9rLw8WHEng7rfA/hlL9Ghoks/3gxaX90+dCXMo1odKbCxTEEBGxUC0aFIOOQGJ8Ot47fNE15IuaoPDO/On1X36wKBgQCwt6H02nLxKY0ILdu8HRVGXcqOOcBQiMIrjjhmt7llAfB5cJKuwq29apyJdRglqWSHXuK3B42reiF3I0fm3+QfihqFUfchU+2N8LcCciNR1BM0l1t/Xkw/FW18lTld0WoTAI/EOE+VEOzzdO542f2m7EBjQZy9hVg4XtlKi1pP5wKBgCXrqVS1siZAbWOvhAs20utVs1Yj/f+0U7FxugbebXbSQyHbd2OPyw/nTvOl2mMzwGXyyT1cDdKqiXia8oExcudeqsNEAAuACSaf6TLBFKL2WBJAvNU0VJOxky40WzcnHpc0ISzlh2HmhRNff5rPVmcZyVfFceCYIHQEf0YSokuLAoGAFqnmXnWpqh4vFS50cOK1+MlMkgL8FBgF9voNZ7cGUtr10U1LspgLGjDTFJns19+qoeXcY6bXV3eZVSM0NHrgUd8vWYvSivatj7egcPLcbsEpGWST+njIhIql+QVWTx7tYLSAu6SRKEf8a5jCgMNMUZ0ZAOHITVINp2UarwHCOl8CgYBenz32mGQapDgw7fyw3aWe5e4i2rC3jHOxJOHSHTAcLzBZ7JrKOIoNtiHU9XWIjRB0kng4a0rDffywxM4YHI+ZMXgvYzHE1Ob2ei3Q/Q52bxkLEwEGrqwXl1kdmCb69imp1T92JBZ3ls2dX7+uJtJiy5KlZilGN61AwMgOxyg7Mg==';
      String decryptedEncryptionPublicKey =
          'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAifuNqUo3yeQ0nu4woe0Vkh/TJU4htzz62HRBhw6EjYbT35Uoi+gYaRKaHTTC0mmKVrKFfWndr0YF6oDdKjNy7n35ZIAIoKQFPLpMwlFrPu7B0GQT34s/3JTtRrmoxe4ldAmjnu7SQOx8qHfUrQCw4v+epMIRqi4vOK4pi3jSsb+6gnziaMHjyQq7Ofvil0KM0F1mKHnga49RxhFjAm7qGsN4ob8CTwaO+hpEe7HmHKvQJaxYr39h3Lw2j8dH0jF3o00uWi9CqIM+4QazTRotVsow+dYWRLzLLIdTmMukyrWLI973jDtc3fXwWU/vcl1zQmd3F152ajhwHrVhD7I6DQIDAQAB';

      String jsonData = jsonEncode({
        "aesPkamPublicKey": encryptedPkamPublicKey,
        "aesPkamPrivateKey": encryptedPkamPrivateKey,
        "aesEncryptPublicKey": encryptedEncryptionPublicKey,
        "aesEncryptPrivateKey": encryptedEncryptionPrivateKey,
        "selfEncryptionKey": "RBQJ7OyTeWPK10Acl0Ga6Kq1CivjOPo2vnUXUodCp5s=",
        "@bob": "RBQJ7OyTeWPK10Acl0Ga6Kq1CivjOPo2vnUXUodCp5s="
      });
      String decryptKey = 'RBQJ7OyTeWPK10Acl0Ga6Kq1CivjOPo2vnUXUodCp5s=';

      when(() => mockKeyChainManager.getPkamPrivateKey(any()))
          .thenAnswer((_) => Future.value('dummy_private_key'));

      var atClientService = AtClientService();
      atClientService.atLookupImpl = mockAtLookupImpl;
      atClientService.keyChainManager = mockKeyChainManager;
      atClientService.atClientManager = mockAtClientManager;

      var authResult = await atClientService.authenticate(
          atSign, atClientPreference,
          jsonData: jsonData, decryptKey: decryptKey);
      expect(authResult, true);
      expect(atChopsImpl!.atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey,
          decryptedPKAMPrivateKey);
      expect(atChopsImpl!.atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey,
          decryptedPKAMPublicKey);
      expect(
          atChopsImpl!.atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey,
          decryptedEncryptionPublicKey);
      expect(
          atChopsImpl!.atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey,
          decryptedEncryptionPrivateKey);
    });

    test('A test to verify when cram secret is populated', () async {
      String pkamPrivateKey = '';
      AtClientPreference atClientPreference = AtClientPreference()
        ..cramSecret = '123';
      when(() => mockAtClientAuthenticator.performInitialAuth(
          any(), atClientPreference)).thenAnswer((_) {
        pkamPrivateKey = 'dummy_private_key';
        return Future.value(true);
      });
      when(() => mockAtClientAuthenticator.atLookUp)
          .thenAnswer((_) => mockAtLookupImpl);
      when(() => mockKeyChainManager.getPkamPrivateKey(any()))
          .thenAnswer((_) => Future.value(pkamPrivateKey));

      var atClientService = AtClientService();
      atClientService.atLookupImpl = mockAtLookupImpl;
      atClientService.keyChainManager = mockKeyChainManager;
      atClientService.atClientManager = mockAtClientManager;
      atClientService.atClientAuthenticator = mockAtClientAuthenticator;

      var authResult = await atClientService.authenticate(
          atSign, atClientPreference,
          status: OnboardingStatus.ACTIVATE);
      expect(authResult, true);
      expect(atChopsImpl!.atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey,
          'dummy_private_key');
      expect(atChopsImpl!.atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey,
          'dummy_public_key');
      expect(
          atChopsImpl!.atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey,
          'dummy_encryption_public_key');
      expect(
          atChopsImpl!.atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey,
          'dummy_encryption_private_key');
    });

    test('A test to verify atChops is set from the keychain manager', () async {
      var atClientService = AtClientService();
      atClientService.atLookupImpl = mockAtLookupImpl;
      atClientService.keyChainManager = mockKeyChainManager;
      atClientService.atClientManager = mockAtClientManager;

      when(() => mockKeyChainManager.getPkamPrivateKey(any()))
          .thenAnswer((_) => Future.value('dummy_private_key'));

      var keysFromChainManager =
          await atClientService.getKeysFromKeyChainManager(atSign);
      var atChops = atClientService.createAtChops(keysFromChainManager);
      expect(atChops.atChopsKeys.atPkamKeyPair?.atPrivateKey.privateKey,
          'dummy_private_key');
      expect(atChops.atChopsKeys.atPkamKeyPair?.atPublicKey.publicKey,
          'dummy_public_key');
      expect(atChops.atChopsKeys.atEncryptionKeyPair?.atPublicKey.publicKey,
          'dummy_encryption_public_key');
      expect(atChops.atChopsKeys.atEncryptionKeyPair?.atPrivateKey.privateKey,
          'dummy_encryption_private_key');
    });
  });

  group('A group of test to validate onboard method', () {
    setUp(() => setUpMethod());

    test('A test to verify onboard method when atSign is populated', () async {
      var atClientService = AtClientService();
      atClientService.atLookupImpl = mockAtLookupImpl;
      atClientService.keyChainManager = mockKeyChainManager;
      atClientService.atClientManager = mockAtClientManager;

      when(() => mockKeyChainManager.getPkamPrivateKey(any()))
          .thenAnswer((_) => Future.value('dummy_private_key'));

      when(() => mockAtLookupImpl.executeCommand(any()))
          .thenAnswer((_) => Future.value('data:dummy_encryption_public_key'));

      var onboardResult = await atClientService.onboard(
          atClientPreference: atClientPreference, atsign: atSign);
      expect(onboardResult, true);
    });

    test('A test to verify onboard method when device is offline', () async {
      var atClientService = AtClientService();
      atClientService.atLookupImpl = mockAtLookupImpl;
      atClientService.keyChainManager = mockKeyChainManager;
      atClientService.atClientManager = mockAtClientManager;

      when(() => mockKeyChainManager.getPkamPrivateKey(any()))
          .thenAnswer((_) => Future.value('dummy_private_key'));
      // When device is offline, it fails to fetch the encryption public key from
      // server and throws network not reachable exceptions
      when(() => mockAtLookupImpl.executeCommand(any()))
          .thenAnswer((_) => throw Exception('Network not reachable'));

      var onboardResult = await atClientService.onboard(
          atClientPreference: atClientPreference, atsign: atSign);
      expect(onboardResult, true);
    });

    test(
        'A test to verify onboard method when atSign is fetched from keychain manager',
        () async {
      var atClientService = AtClientService();
      atClientService.atLookupImpl = mockAtLookupImpl;
      atClientService.keyChainManager = mockKeyChainManager;
      atClientService.atClientManager = mockAtClientManager;

      when(() => mockKeyChainManager.getPkamPrivateKey(any()))
          .thenAnswer((_) => Future.value('dummy_private_key'));
      when(() => mockKeyChainManager.getAtSign())
          .thenAnswer((_) => Future.value(atSign));

      when(() => mockAtLookupImpl.executeCommand(any()))
          .thenAnswer((_) => Future.value('data:dummy_encryption_public_key'));

      var onboardResult =
          await atClientService.onboard(atClientPreference: atClientPreference);
      expect(onboardResult, true);
    });
  });

  group('A group of negative tests to validate authenticate method', () {
    test(
        'A test to verify false is returned when empty atSign is passed to authenticate method',
        () async {
      AtClientPreference atClientPreference = AtClientPreference();
      var atClientService = AtClientService();
      var authResult =
          await atClientService.authenticate('', atClientPreference);
      expect(authResult, false);
    });

    test(
        'A test to verify false is returned when empty jsonData is passed to authenticate method',
        () async {
      AtClientPreference atClientPreference = AtClientPreference();
      var atClientService = AtClientService();
      var authResult = await atClientService
          .authenticate(atSign, atClientPreference, jsonData: '');
      expect(authResult, false);
    });
  });
}

class CustomAtSignMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is AtsignKey) {
      return true;
    }
    return false;
  }
}

class CustomVerbBuilder extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is UpdateVerbBuilder) {
      return true;
    }
    return false;
  }
}

class CustomAtClientPref extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is AtClientPreference) {
      return true;
    }
    return false;
  }
}
