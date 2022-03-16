import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:test/test.dart';
import 'test_utils.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';

void main() {
  var atSign1, atSign2;
  AtClientManager? atSign1AtClientManager, atSign2AtClientManager;

  setUp(() async {
    atSign1 = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    atSign2 = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    atSign1AtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign1, 'me', TestUtils.getPreference(atSign1));
    // await TestUtils.setEncryptionKeys(atSign1);
    var isSyncInProgress = true;
    atSign1AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    atSign2AtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign2, 'me', TestUtils.getPreference(atSign2));
    // await TestUtils.setEncryptionKeys(atSign2);
    isSyncInProgress = true;
    atSign2AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  });

  test('shared key - check sharedKey and checksum in metadata', () async {
    atSign1AtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign1, 'me', TestUtils.getPreference(atSign1));
    var locationKey = AtKey()
      ..key = 'location'
      ..sharedWith = atSign2
      ..sharedBy = atSign1
      ..metadata = Metadata();
    var value = 'Hyd';
    var encryptionService = AtKeyEncryptionManager.get(locationKey, atSign1);
    var encryptedValue = await encryptionService.encrypt(locationKey, value);
    String command = 'update:sharedKeyEnc:${locationKey.metadata?.sharedKeyEnc}:pubKeyCS:${locationKey.metadata?.pubKeyCS}:$atSign2:location.me$atSign1 $encryptedValue';
    print(command);
    var result = await atSign1AtClientManager?.atClient
        .getRemoteSecondary()!
        .executeCommand('$command\n',
            auth: true);
    
    expect(result != null, true);
    var isSyncInProgress = true;
    atSign1AtClientManager?.syncService.sync(onDone: (syncResult) {
      isSyncInProgress = false;
    });
    while (isSyncInProgress) {
      await Future.delayed(Duration(milliseconds: 100));
    }
    atSign2AtClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atSign2, 'me', TestUtils.getPreference(atSign2));
    var getResult = await atSign2AtClientManager?.atClient.get(AtKey()
      ..key = 'location'
      ..sharedBy = atSign1);
    print('metadata is $getResult');
  }, timeout: Timeout(Duration(minutes: 3)));
}