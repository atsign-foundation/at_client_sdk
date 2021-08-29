import 'dart:io';

import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_utils/at_logger.dart';

import 'test_util.dart';

void main() async {
  try {
    AtSignLogger.root_level = 'finer';
    var aliceAtSign = '@alice🛠', bobAtSign = '@bob🛠';
    var alicePreference = TestUtil.getAlicePreference(),
        bobPreference = TestUtil.getBobPreference();

    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(aliceAtSign, 'wavi', alicePreference);
    print('current atSign ${atClientManager.atClient.getCurrentAtSign()}');
    sleep(Duration(minutes:1 ));
    print('*** switching atsign to bob');
    atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(bobAtSign, 'wavi', bobPreference);
    print('current atSign ${atClientManager.atClient.getCurrentAtSign()}');
//    print('*** switching atsign to alice');
//    atClientManager = await AtClientManager.getInstance()
//        .setCurrentAtSign(aliceAtSign, 'wavi', alicePreference);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}
