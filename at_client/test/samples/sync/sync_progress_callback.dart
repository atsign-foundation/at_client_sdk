import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/service/sync/sync_status.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/src/listener/sync_progress_listener.dart';

import '../test_util.dart';

// #TODO move to functional tests

void main() async {
  AtSignLogger.root_level = 'finest';
  final atSign = '@alice🛠';
  var atClientManager = await AtClientManager.getInstance()
      .setCurrentAtSign(atSign, 'wavi', TestUtil.getAlicePreference());
  final progressListener = MySyncProgressListener();
  atClientManager.syncService.addProgressListener(progressListener);
  final atClient = atClientManager.atClient;
  // phone.me@alice🛠
  for (var i = 0; i < 5; i++) {
    var phoneKey = AtKey()..key = 'phone_$i';
    var value = '$i';
    var result = await atClient.put(phoneKey, value);
    print(result);
  }
  print('end of main');
}

class MySyncProgressListener extends SyncProgressListener {
  @override
  void onSync(SyncProgress syncProgress) {
    print('received sync progress: $syncProgress');
  }
}
