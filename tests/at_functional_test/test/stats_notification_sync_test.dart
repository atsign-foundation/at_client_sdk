import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

const notificationIdKey = '_latestNotificationIdv2';

void main() {
  late String atSign;
  late String atSign2;
  late AtClientManager atClientManager;
   String namespace = 'wavi';

  setUp(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atSign2 = ConfigUtil.getYaml()['atSign']['secondAtSign'];

    atClientManager = await TestUtils.initAtClient(atSign, namespace);
    atClientManager.atClient.syncService.sync();
  });

  test('put method - create a key sharing to other atSign', () async {
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
