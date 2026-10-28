import 'dart:io';

import 'package:at_client/at_client.dart';

import '../test_util.dart';
import '../../test_utils/hive_store.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  final atSign = '@alice🛠';
  var atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: atSign,
        namespace: 'wavi',
        preference: TestUtil.getAlicePreference(),
        storage: hiveStoreFor(atSign, TestUtil.getAlicePreference())));
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  for (var i = 0; i < 2; i++) {
    var phoneKey = AtKey()..key = 'ph_$i';
    var value = '$i';
    var result = await atClient.put(phoneKey, value);
    print(result);
  }
  sleep(Duration(minutes: 1));
  atClientManager = AtClientManager.getInstance()
    ..use(await buildAtClient(
        atSign: '@bob🛠',
        namespace: 'wavi',
        preference: TestUtil.getBobPreference(),
        storage: hiveStoreFor('@bob🛠', TestUtil.getBobPreference())));
  // phone.me@alice🛠
  for (var i = 0; i < 2; i++) {
    var phoneKey = AtKey()..key = 'ph_$i';
    var value = '$i';
    var result = await atClientManager.atClient.put(phoneKey, value);
    print(result);
  }
  // execute remote update command from ssl terminal
}
