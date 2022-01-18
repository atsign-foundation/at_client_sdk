import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  late AtClient atClient;
  setUp(() async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
  });
  test('put method - create a key sharing to other atsign', () async {
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getPhoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var getResult = await atClient.get(getPhoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a key with AtKey static factory - public',
      () async {
    var publicKey = AtKey.public('location', namespace: 'wavi').build();
    var value = 'USA';
    var putResult = await atClient.put(publicKey, value);
    expect(putResult, true);
    var getPublicKey = AtKey.public('location', namespace: 'wavi').build();
    var getResult = await atClient.get(getPublicKey);
    expect(getResult.value, value);
  }, timeout: Timeout(Duration(minutes: 10)));

  test('put method - create a sharedWith key with AtKey static factory',
      () async {
    var sharedWithKey = (AtKey.shared('phone', namespace: 'wavi')
          ..sharedWith('@bob🛠'))
        .build();
    var value = '+1 100 200 300';
    var putResult = await atClient.put(sharedWithKey, value);
    expect(putResult, true);
    var getSharedWithKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠'
      ..namespace = 'wavi';
    var getResult = await atClient.get(getSharedWithKey);
    expect(getResult.value, value);
  });

  test('put method - create a self key with AtKey static factory', () async {
    var selfKey = AtKey.self('phone', namespace: 'wavi').build();
    var value = '+1 100 200 300';
    var putResult = await atClient.put(selfKey, value);
    expect(putResult, true);
    var getSelfKey = AtKey()
      ..key = 'phone'
      ..namespace = 'wavi';
    var getResult = await atClient.get(getSelfKey);
    expect(getResult.value, value);
  }, timeout: Timeout(Duration(minutes: 10)));

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
  preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  preference.rootDomain = 'vip.ve.atsign.zone';
  return preference;
}

Uint8List getdata(String filename) {
  var pathToFile = join(dirname(Platform.script.toFilePath()), filename);
  var contents = File(pathToFile).readAsBytesSync();
  return (contents);
}
