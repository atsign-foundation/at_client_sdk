import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'at_demo_credentials.dart' as demo_credentials;
import 'set_encryption_keys.dart';

void main() {
  test('put method - create a key sharing to other atSign', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'phone'
      ..sharedWith = '@bob🛠';
    var value = '+1 100 200 300';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'location'
      ..metadata = (Metadata()..isPublic = true);
    var value = 'California';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a self key with sharedWith populated', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'country'
      ..sharedWith = atsign;
    var value = 'US';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a self key with sharedWith not populated',
      () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()..key = 'mobile';
    var value = '+1 100 200 300';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a key with binary data', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()..isBinary = true);
    var value = _getBinaryData("/test/testData/dev.png");
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key with binary data', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'image'
      ..metadata = (Metadata()
        ..isBinary = true
        ..isPublic = true);
    var value = _getBinaryData("/test/testData/dev.png");
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
  });

  test('put method - create a public key', () async {
    var atsign = '@alice🛠';
    var preference = getAlicePreference(atsign);
    final atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'me', preference);
    var atClient = atClientManager.atClient;
    atClientManager.syncService.sync();
    // To setup encryption keys
    await setEncryptionKeys(atsign, preference);
    // phone.me@alice🛠
    var phoneKey = AtKey()
      ..key = 'city'
      ..metadata = (Metadata()..isPublic = true);
    var value = 'copenhagen';
    var putResult = await atClient.put(phoneKey, value);
    expect(putResult, true);
    var getResult = await atClient.get(phoneKey);
    expect(getResult.value, value);
  });
  tearDown(() async => await tearDownFunc());
}

Future<void> tearDownFunc() async {
  var isExists = await Directory('test/hive').exists();
  if (isExists) {
    Directory('test/hive').deleteSync(recursive: true);
  }
}

Uint8List _getBinaryData(dynamic filePath) {
  var dir = Directory.current.path;
  var pathToFile = '$dir$filePath';
  return File(pathToFile).readAsBytesSync();
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
