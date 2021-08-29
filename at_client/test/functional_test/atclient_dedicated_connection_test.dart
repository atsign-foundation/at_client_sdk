import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  test('put method - create a key sharing to other atsign', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    await AtClientImpl.createClient(atsign, 'me', preference);
    var atClient = await AtClientImpl?.getClient(atsign);
    await atClient!.getSyncManager()!.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var locationKey = AtKey()
      ..key = 'location'
      ..sharedWith = '@bob🛠';
    var value = 'USA';
    // put locationKey using dedicated connection
    var putResult = await atClient.put(locationKey, value, isDedicated: true);
    expect(putResult, true);
    // get locationKey value using dedicated connection
    var getResult = await atClient.get(locationKey, isDedicated: true);
    expect(getResult.value, value);
    // delete locationKey using dedicated connection
    var deleteResult = await atClient.delete(locationKey, isDedicated: true);
    expect(deleteResult, true);
  });
  tearDown(() async => await tearDownFunc());
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

AtClientPreference getAlicePreference(String atsign) {
  var preference = AtClientPreference();
  preference.hiveStoragePath = 'test/hive/client';
  preference.commitLogPath = 'test/hive/client/commit';
  preference.isLocalStoreRequired = true;
  preference.syncStrategy = SyncStrategy.IMMEDIATE;
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}
