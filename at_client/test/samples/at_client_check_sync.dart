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
    var result = await atClientManager.syncService.isInSync();
    print('is in sync? $result');
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void onDone(syncResult) {
  print(syncResult);
}

void onError(syncResult) {
  print('${syncResult.syncStatus} ${syncResult.atClientException}');
}
