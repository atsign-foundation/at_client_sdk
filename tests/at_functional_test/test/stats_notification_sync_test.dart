import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import 'set_encryption_keys.dart';
import 'test_utils.dart';

const notificationIdKey = '_latestNotificationIdv2';

void main() {
   test('put method - create a key sharing to other atSign', () async {
    var atsign = '@alice🛠';
    var atsign2 = '@bob🛠';
    var preference = TestUtils.getPreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.atClient.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var notificationKey = AtKey()
      ..key = notificationIdKey;
    var atNotification = AtNotification('123', notificationIdKey, atsign, atsign2, DateTime.now().millisecondsSinceEpoch, 'key',  true);
    var putResult = await atClient.put(notificationKey, jsonEncode(atNotification.toJson()));
    expect(putResult, true);
    atClientManager.atClient.syncService.sync();
    var getResult = await atClient.getAtKeys(regex: notificationIdKey); 
    assert(!getResult.contains(notificationKey));
  });
  tearDown(() async => await tearDownFunc());
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}