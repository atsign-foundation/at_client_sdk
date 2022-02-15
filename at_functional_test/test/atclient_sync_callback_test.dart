import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/service/sync/sync_status.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_client/src/listener/sync_progress_listener.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;

void main() {
  test('notify updating of a key to sharedWith atSign - using await', () async {
    AtSignLogger.root_level = 'finest';
    final atSign = '@alice🛠';
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign, 'wavi', getPreference(atSign));
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
    await Future.delayed(Duration(seconds: 10));
  });
}

AtClientPreference getPreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}

class MySyncProgressListener extends SyncProgressListener {
  @override
  void onSync(SyncProgress syncProgress) {
    print('received sync progress: $syncProgress');
    expect(syncProgress.syncStatus, SyncStatus.success);
  }
}
