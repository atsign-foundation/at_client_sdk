import 'dart:io';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_utils/at_logger.dart';

import 'test_util.dart';

void main() async {
  try {
    AtSignLogger.root_level = 'finer';
    var atSign = '@alice🛠';
    var preference = TestUtil.getAlicePreference();
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', preference);
    final syncResult = await atClientManager.syncService.sync();
    print(syncResult);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
  exit(1);
}
