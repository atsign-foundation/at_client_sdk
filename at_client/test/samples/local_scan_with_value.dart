import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_commons/at_commons.dart';

import 'test_util.dart';

void main() async {
  try {
    await AtClientImpl.createClient(
        '@alice🛠', 'me', TestUtil.getAlicePreference());
    var atClient = await (AtClientImpl.getClient('@alice🛠'));
    if(atClient == null) {
      print('unable to create at client instance');
      return;
    }
    // Option 1. Get string keys and convert to AtKey
    var result = await atClient.getKeys();
    for (var key in result) {
      var atKey = AtKey.fromString(key);
      var value = await atClient.get(atKey);
      print('$key --> ${value.value}');
    }

    // Option 2. Get AtKeys
    var atKeys = await atClient.getAtKeys();
    for (var key in atKeys) {
      var value = await atClient.get(key);
      print('$key --> ${value.value}');
    }
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void process() {}
