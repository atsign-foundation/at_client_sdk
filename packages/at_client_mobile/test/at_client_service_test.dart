import 'dart:convert';
import 'dart:math';

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
      String jsonData = jsonEncode({
        "aesPkamPublicKey":
            "x/HnmsEMLlG1t1NhlbnB2Yo06lSRuHlrdxDkfPvZHqEI0UE09apcZEKqq/mUlW0pB0X1aFUOPsSlTcjvOvptiRPgo6oD48xANY8TSduQgn94wxsvZlP6xL0Fht8sIz+f1Mkok5SUIbDuVANObFLm2zf9Ipgn2eQ+y2PjjKaI6Dhe3yUr5SFxuv6dp2UeuN5+PGYo2ZCOgeo8WWxThh7PBpgac0/AXCjcQiiNvY59eNQxn/DXEJeXmhBSViI7pCmvW4O7Yo34uTX/TYPvaaBoJlDwwI9q0oR2zDKpi4pObvSdIZhaJ+WEbKy7RACQiN/GfkOLSegWpLXKYYkVps2dRNO251R3uTitfu9m8BO1Gi01H3s2CMKmqi857MkcNcPGU7D1XXW6r8YddfraAPwvUoYGUIcl7dWudwXDJKfjDpXDaklUjZJSGfoSbDvQ6x6a5sV1XZ9WtZJokAIjz4aPd+GCCC+ukSLrTFgGH2TJyFgTAg18Gwdh7SegISwvSCdg6FpiqijMdEPUP6jCRGfT9g==",
        "aesPkamPrivateKey":
            "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",
        "aesEncryptPublicKey":
            "x/HnmsEMLlG1t1NhlbnB2Yo06lSRuHlrdxDkfPvZHqEI0UE09apcZEKqq/mRg38WMlnINGNbBbD/T7jCMrAK8DDiwrcB5oAYKbsNCq66+3p62mgAblProe1zm8gGSwqD9PgXvqX4Oorna152XEnI0ib8FK8k2NBIyDTxucKq1AA8yH5dii5oscCTk1sP38hgGDgsyJKSw9p6eHZM9GCJAvMiRAv4ZheHUiiLhdxxfNASsraycOqZ0zExcRMHlAbsC4z5TJDyvQu4ctihfMAILmms3rhD9Ml5+Cb4kY9IfM2hAaIGW7vDT5bJXQnriryfTHKfXKIVzq7iMPhHo5GSetCQ7Ahb70SmHO5zhlyxQSsCWVkXIbq0sQgS8ukrMsiYJbmyVmXXofhne8rYJqIrTbJEQqgn0bezOST3O4OeVJbYdWRw57hiBeNoJ0LI+kmG6e9sQIllp4927h4k45iLdpumORWckn/JQQJkAVicg0QMVgwvCilEwguzOCggTiAGmVpiqijMdEPUP6jCRGfT9g==",
        "aesEncryptPrivateKey":
            "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",
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

      var authResult =
          await atClientService.authenticate(atSign, atClientPreference);
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
