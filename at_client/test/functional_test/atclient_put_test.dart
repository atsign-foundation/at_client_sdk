import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  test('put method - create a key sharing to other atsign', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance().setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
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
