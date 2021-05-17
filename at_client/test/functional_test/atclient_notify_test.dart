import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

AtClientImpl aliceClient;
AtClientImpl bobClient;

void main() {

  Future<void> setUpClient() async {
    var firstAtsign = '@alice🛠';
    var firstAtsignPreference = getAlicePreference(firstAtsign);
    await AtClientImpl.createClient(firstAtsign, 'me', firstAtsignPreference);
    aliceClient = await AtClientImpl.getClient(firstAtsign);
    aliceClient.getSyncManager().init(firstAtsign, firstAtsignPreference,
        aliceClient.getRemoteSecondary(), aliceClient.getLocalSecondary());
    await aliceClient.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(firstAtsign, firstAtsignPreference);

    var secondAtsign = '@bob🛠';
    var secondAtsignPreference = getBobPreference(secondAtsign);
    await AtClientImpl.createClient(secondAtsign, 'me', secondAtsignPreference);
    bobClient = await AtClientImpl.getClient(secondAtsign);
    bobClient.getSyncManager().init(secondAtsign, secondAtsignPreference,
        bobClient.getRemoteSecondary(), bobClient.getLocalSecondary());
    await bobClient.getSyncManager().sync();
    await setEncryptionKeys(secondAtsign, secondAtsignPreference);
  };

  test('notify method - notifying update of a key to other atsign', () async {
    await setUpClient();
    // notify:update:@bob🛠:company@alice🛠:Atsign
    var companyKey = AtKey()
      ..key = 'company'
      ..sharedWith = '@bob🛠';
    var value = 'Atsign';
    // @alice🛠 notifying company key to @bob🛠
    var notifyResult = await aliceClient.notify(companyKey, value, OperationEnum.update);
    expect(notifyResult, true);
    await Future.delayed(Duration(seconds: 15));
    // @bob🛠 fetching the notifications of @alice🛠
    var notifyListResult = await bobClient.notifyList(regex: '@alice🛠');
    assert(notifyListResult.contains('"key":"@bob🛠:company@alice🛠"'));
  });

   test('notify method - notifying update of a key with message Type,Strategy', () async {
     await setUpClient();
    // phone.me@alice🛠
    var roleKey = AtKey()
      ..key = 'role'
      ..sharedWith = '@bob🛠';
    var value = 'Developer';
    var notifyResult = await aliceClient.notify(roleKey, value, OperationEnum.update, messageType: MessageTypeEnum.key,strategy: StrategyEnum.all);
    expect(notifyResult, true);
    await Future.delayed(Duration(seconds: 10));
    var notifyListResult = await bobClient.notifyList(regex: '@alice🛠');
    print(notifyListResult);
    assert(notifyListResult.contains('"key":"@bob🛠:role@alice🛠"'));
  });

  test('notify method - notifying delete of a key to other atsign', () async {
    // setting up client
    await setUpClient();
    var companyKey = AtKey() 
      ..key = 'company'
      ..sharedWith = '@bob🛠';
    var value = 'Atsign';
    // notify:delete:@bob🛠:company@alice🛠:Atsign
    var notifyResult = await aliceClient.notify(companyKey, value, OperationEnum.delete);
    expect(notifyResult, true);
    await Future.delayed(Duration(seconds: 10));
    var notifyListResult = await bobClient.notifyList(regex: '@alice🛠');
    assert(notifyListResult.contains('"key":"@bob🛠:company@alice🛠","value":null,"operation":"delete"'));
  });

  test('notifyAll method - notifying update of a key to 2 atsigns', () async {
    await setUpClient();
    // phone.me@alice🛠
    var mailKey = AtKey()
      ..key = 'mail'
      ..sharedWith = jsonEncode(['@bob🛠','@purnima🛠']);
    var value = 'alice@atsign.com';
    var notifyResult = await aliceClient.notifyAll(mailKey, value, OperationEnum.update);
    assert(notifyResult.contains('{"@bob🛠":true,"@purnima🛠":true}'));
    await Future.delayed(Duration(seconds: 10));
    var notifyListResult = await bobClient.notifyList(regex: '@alice🛠');
    assert(notifyListResult.contains('"key":"@bob🛠:mail@alice🛠"'));
  });

   test('notifyAll method - notifying update of a key to 2 atsigns', () async {
     await setUpClient();
    // phone.me@alice🛠
    var mobileKey = AtKey()
      ..key = 'mobile'
      ..sharedWith = jsonEncode(['@bob🛠','@purnima🛠']);
    var value = '+91 9092732972';
    var notifyResult = await aliceClient.notifyAll(mobileKey, value, OperationEnum.delete);
    assert(notifyResult.contains('{"@bob🛠":true,"@purnima🛠":true}'));
    await Future.delayed(Duration(seconds: 10));
    var notifyListResult = await bobClient.notifyList(regex: '@alice🛠');
    assert(notifyListResult.contains('"key":"@bob🛠:mobile@alice🛠","value":null,"operation":"delete"'));
  });
  tearDown(() async => await tearDownFunc());
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

AtClientPreference getAlicePreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.syncStrategy = SyncStrategy.IMMEDIATE;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}

AtClientPreference getBobPreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.syncStrategy = SyncStrategy.IMMEDIATE;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}