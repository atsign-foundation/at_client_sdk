import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

/// The tests verify the put and get functionality where key is created using AtKey
/// static factory methods
void main() {
  group('A group of tests to verify positive scenarios of put and get', () {
    test('put method - create a key sharing to other atSign', () async {
      var atsign = '@alice🛠';
      var preference = getAlicePreference(atsign);
      final atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atsign, 'wavi', preference);
      var atClient = atClientManager.atClient;
      atClientManager.atClient.syncService.sync();
      // To setup encryption keys
      await setEncryptionKeys(atsign, preference);
      // phone.wavi@alice🛠
      var putPhoneKey = (AtKey.shared('phone', namespace: 'wavi')
            ..sharedWith('@bob🛠'))
          .build();
      var value = '+1 100 200 300';
      var putResult = await atClient.put(putPhoneKey, value);
      expect(putResult, true);
      var getPhoneKey = AtKey()
        ..key = 'phone'
        ..sharedWith = '@bob🛠';
      var getResult = await atClient.get(getPhoneKey);
      expect(getResult.value, value);
    });

    test('put method - create a public key', () async {
      var atsign = '@alice🛠';
      var preference = getAlicePreference(atsign);
      final atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atsign, 'wavi', preference);
      var atClient = atClientManager.atClient;
      atClientManager.atClient.syncService.sync();
      // To setup encryption keys
      await setEncryptionKeys(atsign, preference);
      // location.wavi@alice🛠
      var putKey = AtKey.public('location', namespace: 'wavi').build();
      var value = 'California';
      var putResult = await atClient.put(putKey, value);
      expect(putResult, true);
      var getKey = AtKey()
        ..key = 'location'
        ..metadata = (Metadata()..isPublic = true);
      var getResult = await atClient.get(getKey);
      expect(getResult.value, value);
    });

    test('put method - create a self key with sharedWith populated', () async {
      var atsign = '@alice🛠';
      var preference = getAlicePreference(atsign);
      final atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atsign, 'wavi', preference);
      var atClient = atClientManager.atClient;
      atClientManager.atClient.syncService.sync();
      // To setup encryption keys
      await setEncryptionKeys(atsign, preference);
      // country.wavi@alice🛠
      var putKey = (AtKey.shared('country', namespace: 'wavi')
            ..sharedWith(atsign))
          .build();
      var value = 'US';
      var putResult = await atClient.put(putKey, value);
      expect(putResult, true);
      var getKey = AtKey()
        ..key = 'country'
        ..sharedWith = atsign;
      var getResult = await atClient.get(getKey);
      expect(getResult.value, value);
    });

    test('put method - create a self key with sharedWith not populated',
        () async {
      var atsign = '@alice🛠';
      var preference = getAlicePreference(atsign);
      final atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atsign, 'wavi', preference);
      var atClient = atClientManager.atClient;
      atClientManager.atClient.syncService.sync();
      // To setup encryption keys
      await setEncryptionKeys(atsign, preference);
      // mobile.wavi@alice🛠
      var putKey = AtKey.self('mobile', namespace: 'wavi').build();
      var value = '+1 100 200 300';
      var putResult = await atClient.put(putKey, value);
      expect(putResult, true);
      var getKey = AtKey()..key = 'mobile';
      var getResult = await atClient.get(getKey);
      expect(getResult.value, value);
    });
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
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}
