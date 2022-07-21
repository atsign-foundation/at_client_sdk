import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

const notificationIdKey = '_latestNotificationIdv2';

void main() {
   test('put method - create a key sharing to other atSign', () async {
    var atsign = '@alice🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var notificationKey = AtKey()
      ..key = notificationIdKey;
    var value = '-1';
    var putResult = await atClient.put(notificationKey, value);
    expect(putResult, true);
    atClientManager.syncService.sync();
    var getResult = await atClient.getAtKeys(regex: notificationIdKey); 
    assert(!getResult.contains(notificationKey));
  });
  tearDownFunc();
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}