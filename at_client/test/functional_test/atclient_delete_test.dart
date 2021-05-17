import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  AtClientImpl aliceClient;

  Future<void> setUpClient() async {
    var firstAtsign = '@alice🛠';
    var firstAtsignPreference = getAlicePreference(firstAtsign);
    await AtClientImpl.createClient(firstAtsign, 'me', firstAtsignPreference);
    aliceClient = await AtClientImpl.getClient(firstAtsign);
    aliceClient.getSyncManager().init(firstAtsign, firstAtsignPreference,
        aliceClient.getRemoteSecondary(), aliceClient.getLocalSecondary());
    await aliceClient.getSyncManager().sync();
    // To setup encryption keys
    await setEncryptionKeys(firstAtsign, firstAtsignPreference);
  }

  test('delete method - delete a key sharing to other atsign', () async {
    await setUpClient();
    // @bob🛠:phone.me@alice🛠
    var metadata = Metadata()..namespaceAware = true;
    var phoneKey = AtKey()
      ..key = 'phone'
      ..namespace = '.me'
      ..metadata = metadata
      ..sharedWith = '@bob🛠';
    var deleteResult = await aliceClient.delete(phoneKey);
    expect(deleteResult, true);
  });

  test('delete method - delete a public key', () async {
    await setUpClient();
    var metadata = Metadata()..isPublic = true;
    var nameKey = AtKey()
      ..key = 'name'
      ..metadata = metadata;
    var deleteResult = await aliceClient.delete(nameKey);
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
