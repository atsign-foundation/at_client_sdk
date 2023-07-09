import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/at_keys_intialializer.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

const notificationIdKey = '_latestNotificationIdv2';

void main() {
  test('put method - create a key sharing to other atSign', () async {
    var atSign = '@alice🛠';
    var atSign2 = '@bob🛠';
    var preference = TestUtils.getPreference(atSign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'me', preference);
    atClientManager.atClient.syncService.sync();
    // To setup encryption keys
    await AtEncryptionKeysLoader.getInstance()
        .setEncryptionKeys(atClientManager.atClient, atSign);
    // phone.me@alice🛠
    var notificationKey = AtKey()..key = notificationIdKey;
    var atNotification = AtNotification('123', notificationIdKey, atSign,
        atSign2, DateTime.now().millisecondsSinceEpoch, 'key', true);
    var putResult = await atClientManager.atClient
        .put(notificationKey, jsonEncode(atNotification.toJson()));
    expect(putResult, true);
    atClientManager.atClient.syncService.sync();
    var getResult =
        await atClientManager.atClient.getAtKeys(regex: notificationIdKey);
    assert(!getResult.contains(notificationKey));
  });
}
