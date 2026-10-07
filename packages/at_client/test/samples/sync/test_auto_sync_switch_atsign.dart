import 'dart:io';

import 'package:at_client/at_client.dart';

import '../test_util.dart';

void main() async {
  AtSignLogger.root_level = 'finer';
  final atSign = '@alice🛠';
  var atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(atSign, 'wavi', TestUtil.getAlicePreference());
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  for (var i = 0; i < 2; i++) {
    var phoneKey = AtKey()..key = 'ph_$i';
    var value = '$i';
    var result = await atClient.put(phoneKey, value);
    print(result);
  }
  sleep(Duration(minutes: 1));
  atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign('@bob🛠', 'wavi', TestUtil.getBobPreference());
  // phone.me@alice🛠
  for (var i = 0; i < 2; i++) {
    var phoneKey = AtKey()..key = 'ph_$i';
    var value = '$i';
    var result = await atClientManager.atClient.put(phoneKey, value);
    print(result);
  }
  // execute remote update command from ssl terminal
}
